import re
import sys

import urllib.parse
import urllib.request

pastebin_api_key = sys.argv[1]
filename = sys.argv[2]

class API:
    def __init__(self, dev_key, **kwargs):
        self.dev_key = dev_key
        if kwargs:
            self.other_args = kwargs
        else:
            self.other_args = {}

    def paste(self, api_paste_code: str, **kwargs) -> str:
        site = "https://pastebin.com/api/api_post.php"
        req_dic = {
            "api_dev_key": self.dev_key,
            "api_option": "paste",
            "api_paste_code": api_paste_code
        }
        req_dic.update(kwargs.items())
        req_dic.update(self.other_args.items())
        data = urllib.parse.urlencode(req_dic).encode()
        request = urllib.request.Request(site, method='POST')
        resp = urllib.request.urlopen(request, data)
        content = resp.read().decode(resp.headers.get_content_charset())
        code = re.search(r'\/(\w+?)$', string=content).groups()[0]
        return code


def upload(s):
    api = API(pastebin_api_key)
    link = api.paste(api_paste_code=s, api_paste_name='CCTweakedLogistics', api_paste_format='lua', api_paste_expire_date='1H', api_paste_private='1')
    code = link
    print(f"Done, to import into the computer run \npastebin get {code} {filename}")

def exclude(s):
    return re.sub(r'-- PASTEBIN EXCLUDE(.*?)-- END PASTEBIN EXCLUDE\s*?\n', '', s, flags=re.DOTALL | re.MULTILINE)

if __name__ == '__main__':
    with open(filename, 'r') as f:
        program = f.read()

        upload(exclude(program))