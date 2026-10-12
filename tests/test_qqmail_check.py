import importlib.util
import pathlib
import tempfile
import unittest


MODULE_PATH = pathlib.Path(__file__).parents[1] / "src" / "qqmail_check.py"
SPEC = importlib.util.spec_from_file_location("qqmail_check", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class QQMailCheckTests(unittest.TestCase):
    def test_classification(self):
        self.assertEqual(MODULE.classify("GitHub", "Your verification code", ""), "验证码")
        self.assertEqual(MODULE.classify("银行", "本月信用卡账单", ""), "账单支付")
        self.assertEqual(MODULE.classify("商城", "限时优惠", "退订"), "推广订阅")
        self.assertEqual(MODULE.classify("朋友", "周末见", "一起吃饭"), "普通邮件")

    def test_state_round_trip(self):
        with tempfile.TemporaryDirectory() as directory:
            path = str(pathlib.Path(directory) / "state.json")
            expected = {"email": "example@qq.com", "uidvalidity": 1, "last_uid": 10}
            MODULE.write_state(path, expected)
            self.assertEqual(MODULE.read_state(path), expected)

    def test_mime_header(self):
        encoded = "=?UTF-8?B?5rWL6K+V6YKu5Lu2?="
        self.assertEqual(MODULE.decode_mime(encoded), "测试邮件")


if __name__ == "__main__":
    unittest.main()
