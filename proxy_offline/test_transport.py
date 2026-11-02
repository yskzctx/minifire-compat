from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
import hashlib
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import queue
import ssl
import threading
import pytest

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

from proxy_offline.adapter import Journal
from proxy_offline.test_transform import protocol
from proxy_offline.transport import make_server


@contextmanager
def running(server):
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    try:yield server.server_address
    finally:server.shutdown();server.server_close();thread.join(timeout=3)


def contexts(tmp_path):
    key=ec.generate_private_key(ec.SECP256R1())
    subject=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'localhost test only')])
    now=datetime.now(timezone.utc)
    cert=(x509.CertificateBuilder().subject_name(subject).issuer_name(subject).public_key(key.public_key())
          .serial_number(x509.random_serial_number()).not_valid_before(now-timedelta(minutes=1))
          .not_valid_after(now+timedelta(days=1)).add_extension(x509.SubjectAlternativeName([
              x509.DNSName('localhost'),x509.IPAddress(ipaddress.ip_address('127.0.0.1'))]),critical=False)
          .sign(key,hashes.SHA256()))
    certfile=tmp_path/'cert.pem';keyfile=tmp_path/'key.pem'
    certfile.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    keyfile.write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
    keyfile.chmod(0o600)
    server=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);server.load_cert_chain(certfile,keyfile)
    client=ssl.create_default_context(cafile=str(certfile))
    return server,client


@pytest.mark.parametrize('valid_signature',[True,False])
def test_tls_client_through_bridge_reaches_tls_upstream_with_resigned_body(tmp_path,valid_signature):
    server_context,client_context=contexts(tmp_path)
    received=queue.Queue(); material=b'LOCAL-TEST-MATERIAL'
    class Upstream(BaseHTTPRequestHandler):
        def do_POST(self):
            body=self.rfile.read(int(self.headers['Content-Length']))
            received.put((body,self.headers['sign'],self.headers['unique']))
            self.send_response(200);self.end_headers();self.wfile.write(b'fixture accepted')
        def log_message(self,*args):pass
    upstream=ThreadingHTTPServer(('127.0.0.1',0),Upstream)
    upstream.socket=server_context.wrap_socket(upstream.socket,server_side=True)
    with running(upstream) as address:
        bridge=make_server(('127.0.0.1',0),f'https://127.0.0.1:{address[1]}',protocol,
                           material,Journal(tmp_path/'events.jsonl'),server_context,client_context)
        with running(bridge) as proxy:
            req=protocol.new('md.ApiLoginRequest');req.PhoneOs=1;req.ChannelID=23
            req.Version=req.VersionName='1.0.77';req.OpenToken='PRIVATE-SYNTHETIC-TOKEN'
            body=req.SerializeToString();unique='fixture-time'
            sign=hashlib.sha1(body+material+unique.encode()).hexdigest().upper()
            if not valid_signature:sign='0'*40
            client=http.client.HTTPSConnection(*proxy,context=client_context,timeout=3)
            client.request('POST','/api/user/login',body,{'sign':sign,'unique':unique})
            response=client.getresponse();assert response.status==200
            assert response.read()==b'fixture accepted';client.close()
    forwarded,new_sign,new_unique=received.get_nowait()
    parsed=protocol.parse('md.ApiLoginRequest',forwarded)
    if valid_signature:
        assert parsed.PhoneOs==2 and parsed.ChannelID==888
        assert new_sign==hashlib.sha1(forwarded+material+new_unique.encode()).hexdigest().upper()
    else:
        assert forwarded==body and new_sign==sign
    log=(tmp_path/'events.jsonl').read_text()
    events=[json.loads(line) for line in log.splitlines()]
    expected={'signature_verified','request_rewritten','forward_succeeded'} if valid_signature else {'signature_unverified','forward_succeeded'}
    assert {event['event'] for event in events}>=expected
    assert len({event['request_id'] for event in events})==1
    assert 'PRIVATE-SYNTHETIC-TOKEN' not in log and sign not in log


def test_upstream_certificate_verification_is_not_disabled(tmp_path):
    server_context,client_context=contexts(tmp_path)
    upstream=ThreadingHTTPServer(('127.0.0.1',0),BaseHTTPRequestHandler)
    upstream.socket=server_context.wrap_socket(upstream.socket,server_side=True)
    journal=Journal(tmp_path/'events.jsonl')
    with running(upstream) as address:
        bridge=make_server(('127.0.0.1',0),f'https://127.0.0.1:{address[1]}',protocol,b'fixture',
                           journal,server_context,ssl.create_default_context())
        with running(bridge) as proxy:
            client=http.client.HTTPSConnection(*proxy,context=client_context,timeout=3)
            client.request('GET','/fixture')
            response=client.getresponse();assert response.status==502;response.read();client.close()
    assert 'upstream_tls_failed' in (tmp_path/'events.jsonl').read_text()
