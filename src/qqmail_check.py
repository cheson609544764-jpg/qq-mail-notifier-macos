#!/usr/bin/env python3
"""Check QQ Mail over IMAP and emit one JSON result to stdout.

The authorization code is read from stdin. It is never written to disk or logs.
"""

import argparse
import email
import html
import imaplib
import json
import os
import re
import socket
import ssl
import sys
import tempfile
from email.header import decode_header
from email.policy import default
from email.utils import parseaddr


HOST = "imap.qq.com"
PORT = 993
MAX_NEW_MAILS = 20
MAX_UNREAD_MAILS = 12
MESSAGE_BYTES = 12 * 1024


CLASSIFIERS = (
    (
        "验证码",
        re.compile(
            r"验证码|校验码|动态码|登录代码|一次性密码|one[- ]?time|\botp\b|verification code|security code",
            re.I,
        ),
    ),
    (
        "安全提醒",
        re.compile(
            r"异地登录|新设备|安全提醒|安全警告|风险|密码|账号异常|可疑|被盗|login alert|security alert|password|suspicious",
            re.I,
        ),
    ),
    (
        "账单支付",
        re.compile(
            r"账单|支付|付款|交易|消费|扣款|退款|发票|收据|信用卡|银行卡|invoice|receipt|payment|refund|transaction",
            re.I,
        ),
    ),
    (
        "工作事务",
        re.compile(
            r"会议|面试|合同|审批|项目|报价|招聘|录用|客户|工作|简历|截止|邀请函|offer|meeting|interview|contract|project",
            re.I,
        ),
    ),
    (
        "行程物流",
        re.compile(
            r"快递|物流|发货|签收|航班|机票|酒店|行程|车票|delivery|shipment|flight|hotel|itinerary",
            re.I,
        ),
    ),
    (
        "推广订阅",
        re.compile(
            r"优惠|促销|营销|推广|折扣|限时|会员专享|退订|unsubscribe|newsletter|promotion|sale|discount",
            re.I,
        ),
    ),
)


def decode_mime(value):
    if not value:
        return ""
    pieces = []
    for part, charset in decode_header(str(value)):
        if isinstance(part, bytes):
            for encoding in (charset, "utf-8", "gb18030", "latin-1"):
                if not encoding:
                    continue
                try:
                    pieces.append(part.decode(encoding, errors="replace"))
                    break
                except (LookupError, UnicodeDecodeError):
                    continue
        else:
            pieces.append(part)
    return "".join(pieces).strip()


def clean_text(value):
    if not value:
        return ""
    value = re.sub(r"(?is)<(script|style).*?>.*?</\1>", " ", value)
    value = re.sub(r"(?s)<[^>]+>", " ", value)
    value = html.unescape(value)
    value = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", " ", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def decode_payload(part):
    payload = part.get_payload(decode=True)
    if payload is None:
        raw = part.get_payload()
        return raw if isinstance(raw, str) else ""
    charset = part.get_content_charset()
    for encoding in (charset, "utf-8", "gb18030", "latin-1"):
        if not encoding:
            continue
        try:
            return payload.decode(encoding, errors="replace")
        except (LookupError, UnicodeDecodeError):
            continue
    return ""


def make_snippet(message):
    plain = []
    rich = []
    parts = message.walk() if message.is_multipart() else (message,)
    for part in parts:
        if part.get_content_disposition() == "attachment":
            continue
        content_type = part.get_content_type()
        if content_type == "text/plain":
            plain.append(decode_payload(part))
        elif content_type == "text/html":
            rich.append(decode_payload(part))
    text = clean_text(" ".join(plain) or " ".join(rich))
    # Avoid making a notification mostly out of long URLs.
    text = re.sub(r"https?://\S{45,}", "[链接]", text)
    return text[:160]


def classify(sender, subject, snippet):
    haystack = " ".join((sender, subject, snippet))
    for label, pattern in CLASSIFIERS:
        if pattern.search(haystack):
            return label
    return "普通邮件"


def read_state(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
            return data if isinstance(data, dict) else {}
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}


def write_state(path, value):
    directory = os.path.dirname(path)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="state-", suffix=".json", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False)
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def parse_uidvalidity(connection):
    response = connection.response("UIDVALIDITY")
    if response and len(response) > 1 and response[1]:
        raw = response[1][0]
        if isinstance(raw, bytes):
            raw = raw.decode("ascii", errors="ignore")
        match = re.search(r"\d+", str(raw))
        if match:
            return int(match.group(0))
    return 0


def search_uids(connection, criterion):
    status, data = connection.uid("search", None, criterion)
    if status != "OK":
        raise RuntimeError("无法读取收件箱邮件列表。")
    if not data or not data[0]:
        return []
    return [int(value) for value in data[0].split() if value.isdigit()]


def all_uids(connection):
    return search_uids(connection, "ALL")


def fetch_message(connection, uid):
    query = "(UID BODY.PEEK[]<0.%d>)" % MESSAGE_BYTES
    status, data = connection.uid("fetch", str(uid), query)
    if status != "OK":
        raise RuntimeError("无法读取新邮件。")
    raw_chunks = []
    for item in data or []:
        if isinstance(item, tuple) and len(item) > 1 and isinstance(item[1], bytes):
            raw_chunks.append(item[1])
    raw = b"".join(raw_chunks)
    if not raw:
        raise RuntimeError("新邮件内容为空。")

    message = email.message_from_bytes(raw, policy=default)
    subject = decode_mime(message.get("Subject")) or "（无主题）"
    display_name, address = parseaddr(decode_mime(message.get("From")))
    sender = display_name.strip() or address.strip() or "未知发件人"
    if display_name and address:
        sender = "%s <%s>" % (display_name.strip(), address.strip())
    snippet = make_snippet(message)
    return {
        "uid": uid,
        "subject": subject[:180],
        "sender": sender[:180],
        "snippet": snippet,
        "category": classify(sender, subject, snippet),
    }


def run(email_address, authorization_code, state_path):
    context = ssl.create_default_context()
    connection = imaplib.IMAP4_SSL(HOST, PORT, ssl_context=context, timeout=25)
    try:
        connection.login(email_address, authorization_code)
        status, _ = connection.select("INBOX", readonly=True)
        if status != "OK":
            raise RuntimeError("无法打开 QQ 邮箱收件箱。")

        uidvalidity = parse_uidvalidity(connection)
        uids = all_uids(connection)
        unread_uids = search_uids(connection, "UNSEEN")
        latest_uid = max(uids, default=0)
        state = read_state(state_path)

        initialized = (
            not state
            or state.get("email") != email_address
            or int(state.get("uidvalidity", 0)) != uidvalidity
        )
        last_uid = latest_uid if initialized else int(state.get("last_uid", 0))
        new_uids = [] if initialized else [uid for uid in uids if uid > last_uid]
        selected_uids = new_uids[-MAX_NEW_MAILS:]
        visible_unread_uids = list(reversed(unread_uids[-MAX_UNREAD_MAILS:]))

        cached = state.get("message_cache", {}) if not initialized else {}
        if not isinstance(cached, dict):
            cached = {}
        message_cache = {}
        failed = 0

        def get_message(uid):
            nonlocal failed
            key = str(uid)
            item = cached.get(key)
            if isinstance(item, dict) and item.get("uid") == uid:
                message_cache[key] = item
                return item
            try:
                item = fetch_message(connection, uid)
                message_cache[key] = item
                return item
            except Exception:
                failed += 1
                return None

        # Fetch each UID at most once. The newest unread messages are cached locally
        # so the widget does not redownload their bodies every minute.
        items_by_uid = {}
        for uid in list(dict.fromkeys(selected_uids + visible_unread_uids)):
            item = get_message(uid)
            if item:
                items_by_uid[uid] = item

        mails = [items_by_uid[uid] for uid in selected_uids if uid in items_by_uid]
        unread = [items_by_uid[uid] for uid in visible_unread_uids if uid in items_by_uid]
        next_last_uid = max(new_uids, default=last_uid)
        write_state(
            state_path,
            {
                "email": email_address,
                "uidvalidity": uidvalidity,
                "last_uid": next_last_uid,
                "message_cache": message_cache,
            },
        )
        return {
            "ok": True,
            "initialized": initialized,
            "new": mails,
            "unread": unread,
            "unread_total": len(unread_uids),
            "skipped": max(0, len(new_uids) - len(selected_uids)),
            "failed": failed,
            "latest_uid": next_last_uid,
        }
    finally:
        try:
            connection.logout()
        except Exception:
            pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--email", required=True)
    parser.add_argument("--state", required=True)
    args = parser.parse_args()
    authorization_code = sys.stdin.readline().strip()
    if not authorization_code:
        print(json.dumps({"ok": False, "error": "没有读取到 QQ 邮箱授权码。"}, ensure_ascii=False))
        return 2
    try:
        result = run(args.email.strip(), authorization_code, args.state)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except imaplib.IMAP4.error:
        print(
            json.dumps(
                {
                    "ok": False,
                    "kind": "authentication",
                    "error": "QQ 邮箱登录失败，请检查 IMAP 是否已开启以及授权码是否正确。",
                },
                ensure_ascii=False,
            )
        )
        return 3
    except (socket.timeout, TimeoutError):
        print(json.dumps({"ok": False, "error": "连接 QQ 邮箱超时，稍后会自动重试。"}, ensure_ascii=False))
        return 4
    except (OSError, ssl.SSLError):
        print(json.dumps({"ok": False, "error": "暂时无法连接 QQ 邮箱，稍后会自动重试。"}, ensure_ascii=False))
        return 5
    except Exception as exc:
        safe_message = str(exc).strip() or "检查邮件时发生未知错误。"
        print(json.dumps({"ok": False, "error": safe_message[:240]}, ensure_ascii=False))
        return 6
    finally:
        authorization_code = ""


if __name__ == "__main__":
    raise SystemExit(main())
