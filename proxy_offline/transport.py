"""Experimental loopback HTTPS bridge. No Android interception is installed.

Only a fixed upstream is reachable. Certificate verification remains enabled.
The signing formula and header names still need real-client validation.
"""
import argparse
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import ssl
from urllib.parse import urlsplit
import uuid

from .adapter import Journal, SignedLoginAdapter
from .transform import ProtocolTransformer

HOP={'connection','keep-alive','proxy-authenticate','proxy-authorization','te',
     'trailer','transfer-encoding','upgrade','host','content-length'}
MAX_BODY=2*1024*1024


def make_server(address,upstream,protocol,material,journal,server_context,upstream_context):
    target=urlsplit(upstream)
    if target.scheme!='https' or not target.hostname or target.username or target.password or target.query or target.fragment or target.path not in ('','/'):
        raise ValueError('upstream must be a fixed HTTPS origin')
    if address[0] not in ('127.0.0.1','::1'):raise ValueError('bridge must bind loopback')
    if not upstream_context.check_hostname or upstream_context.verify_mode!=ssl.CERT_REQUIRED:
        raise ValueError('upstream certificate verification is required')
    adapter=SignedLoginAdapter(protocol,journal)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args):pass

        def _handle(self):
            self.connection.settimeout(10)
            request_id=uuid.uuid4().hex
            lengths=self.headers.get_all('Content-Length') or []
            if len(lengths)>1 or self.headers.get('Transfer-Encoding'):
                journal.record('request_rejected',request_id,status_code=400)
                self.send_error(400,'Unsupported request framing');return
            try:length=int(lengths[0]) if lengths else 0
            except ValueError:length=-1
            if not 0<=length<=MAX_BODY:
                journal.record('request_rejected',request_id,status_code=413)
                self.send_error(413,'Request size limit');return
            body=self.rfile.read(length)
            if len(body)!=length:
                journal.record('request_rejected',request_id,status_code=400)
                self.send_error(400,'Incomplete request');return
            nominated={part.strip().lower() for part in self.headers.get('Connection','').split(',')}
            headers={key:value for key,value in self.headers.items() if key.lower() not in HOP|nominated}
            if self.command=='POST' and urlsplit(self.path).path=='/api/user/login' and not self.headers.get('Content-Encoding'):
                signs=self.headers.get_all('sign') or []
                uniques=self.headers.get_all('unique') or []
                if len(signs)==1 and len(uniques)==1:
                    result=adapter.terminal(body,uniques[0],signs[0],material,request_id=request_id)
                    body=result.body
                    headers={key:value for key,value in headers.items() if key.lower()!='sign'}
                    headers['sign']=result.signature
                else:journal.record('signature_unverified',request_id,input_bytes=len(body))
            connection=http.client.HTTPSConnection(target.hostname,target.port or 443,context=upstream_context,timeout=10)
            journal.record('forward_started',request_id,input_bytes=len(body))
            started=False
            try:
                path=urlsplit(self.path)
                if path.scheme or path.netloc:raise ValueError('absolute request target rejected')
                connection.request(self.command,self.path,body=body,headers=headers)
                response=connection.getresponse()
                self.send_response(response.status)
                response_nominated={part.strip().lower() for part in (response.getheader('Connection') or '').split(',')}
                for key,value in response.getheaders():
                    if key.lower() not in HOP|response_nominated:self.send_header(key,value)
                self.send_header('Connection','close');self.end_headers()
                started=True
                expected=response.length
                count=0
                while True:
                    chunk=response.read(65536)
                    if not chunk:break
                    self.wfile.write(chunk)
                    count+=len(chunk)
                if expected is not None and count!=expected:raise http.client.IncompleteRead(b'')
                journal.record('forward_succeeded',request_id,status_code=response.status)
            except ssl.SSLError:
                journal.record('upstream_tls_failed',request_id,status_code=502)
                if not started:self.send_error(502,'Upstream TLS failed')
            except (OSError,ValueError,http.client.HTTPException):
                journal.record('upstream_io_failed',request_id,status_code=502)
                if not started:self.send_error(502,'Upstream request failed')
            finally:connection.close();self.close_connection=True

        do_GET=_handle
        do_POST=_handle

    server=ThreadingHTTPServer(address,Handler)
    server.daemon_threads=True
    server.socket=server_context.wrap_socket(server.socket,server_side=True)
    return server


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--upstream',required=True)
    parser.add_argument('--bundle',type=Path,required=True)
    parser.add_argument('--material-file',type=Path,required=True)
    parser.add_argument('--cert',required=True);parser.add_argument('--key',required=True)
    parser.add_argument('--port',type=int,default=18443)
    parser.add_argument('--journal',type=Path,required=True)
    parser.add_argument('--target-version',default='1.0.79')
    args=parser.parse_args()
    material=args.material_file.read_bytes()
    if not 1<=len(material)<=256:parser.error('material file must contain 1..256 bytes')
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(args.cert,args.key)
    server=make_server(('127.0.0.1',args.port),args.upstream,ProtocolTransformer(args.bundle,args.target_version),
                       material,Journal(args.journal),context,ssl.create_default_context())
    try:server.serve_forever()
    except KeyboardInterrupt:pass
    finally:server.server_close()


if __name__=='__main__':main()
