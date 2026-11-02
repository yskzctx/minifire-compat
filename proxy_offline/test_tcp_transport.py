import socket
import socketserver
import struct

from proxy_offline.adapter import Journal
from proxy_offline.test_transport import running
from proxy_offline.tcp_transport import make_lobby_server


def test_segmented_tcp_stream_is_reframed_and_response_returned(tmp_path):
    class Echo(socketserver.BaseRequestHandler):
        def handle(self):
            while True:
                data=self.request.recv(7)
                if not data:break
                self.request.sendall(data)
    upstream=socketserver.ThreadingTCPServer(('127.0.0.1',0),Echo)
    with running(upstream) as destination:
        proxy=make_lobby_server(('127.0.0.1',0),destination,lambda body:(body+b'!',True),Journal(tmp_path/'events.jsonl'))
        with running(proxy) as address:
            with socket.create_connection(address,timeout=3) as client:
                frame=b'SP'+struct.pack('<I',5)+b'hello'
                for value in frame:client.sendall(bytes([value]))
                client.shutdown(socket.SHUT_WR)
                output=b''
                while True:
                    data=client.recv(4096)
                    if not data:break
                    output+=data
    assert output==b'SP'+struct.pack('<I',6)+b'hello!'
    text=(tmp_path/'events.jsonl').read_text()
    assert 'lobby_frame_rewritten' in text and 'lobby_stream_closed' in text


def test_non_sp_tcp_stream_is_forwarded_without_changes(tmp_path):
    class Echo(socketserver.BaseRequestHandler):
        def handle(self):
            while data:=self.request.recv(4096):self.request.sendall(data)
    upstream=socketserver.ThreadingTCPServer(('127.0.0.1',0),Echo)
    with running(upstream) as destination:
        proxy=make_lobby_server(('127.0.0.1',0),destination,lambda body:(b'incorrect',True),Journal(tmp_path/'events.jsonl'))
        with running(proxy) as address:
            with socket.create_connection(address,timeout=3) as client:
                original=b'unknown protocol stays intact'
                client.sendall(original);client.shutdown(socket.SHUT_WR)
                result=b''
                while data:=client.recv(4096):result+=data
    assert result==original
    assert 'lobby_protocol_unknown' in (tmp_path/'events.jsonl').read_text()
