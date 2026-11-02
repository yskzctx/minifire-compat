"""Verified byte adapter for an eventual external transport.

This is transport independent and has not been validated against game traffic.
It never installs hooks, redirects sockets, or changes certificate stores.
"""
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import threading
import uuid

from .signature import resign_if_verified


class Journal:
    EVENTS={'signature_verified','signature_unverified','request_rewritten','request_unchanged'}
    FIELDS={'input_bytes','output_bytes','target_version'}

    def __init__(self,path):
        self.path=Path(path)
        self.lock=threading.Lock()
        self.last_error=None

    def record(self,event,request_id,**details):
        if event not in self.EVENTS or not re.fullmatch(r'[A-Za-z0-9-]{1,64}',request_id):
            raise ValueError('invalid diagnostic event')
        if details.keys()-self.FIELDS:raise ValueError('unsupported diagnostic field')
        for key,value in details.items():
            if key=='target_version':
                if not isinstance(value,str) or not re.fullmatch(r'\d+\.\d+\.\d+',value):raise ValueError('invalid version')
            elif type(value) is not int or not 0<=value<=16*1024*1024:raise ValueError('invalid byte count')
        entry={'time':datetime.now(timezone.utc).isoformat(),'event':event,'request_id':request_id,**details}
        encoded=(json.dumps(entry,ensure_ascii=True,separators=(',',':'))+'\n').encode()
        with self.lock:
            try:
                self.path.parent.mkdir(parents=True,exist_ok=True)
                if self.path.exists() and self.path.stat().st_size>1024*1024:
                    os.replace(self.path,self.path.with_suffix(self.path.suffix+'.1'))
                descriptor=os.open(self.path,os.O_WRONLY|os.O_APPEND|os.O_CREAT,0o600)
                with os.fdopen(descriptor,'ab') as stream:stream.write(encoded)
                self.last_error=None
                return True
            except OSError as error:
                self.last_error={'type':type(error).__name__,'errno':error.errno}
                return False


@dataclass(frozen=True)
class Result:
    body: bytes
    signature: str
    changed: bool


class SignedLoginAdapter:
    def __init__(self,protocol,journal):
        self.protocol=protocol
        self.journal=journal

    def terminal(self,body,unique,signature,material):
        request_id=uuid.uuid4().hex
        if resign_if_verified(body,body,unique,material,signature) is None:
            self.journal.record('signature_unverified',request_id,input_bytes=len(body))
            return Result(body,signature,False)
        self.journal.record('signature_verified',request_id,input_bytes=len(body))
        rewritten,changed=self.protocol.terminal_login(body)
        if not changed:
            self.journal.record('request_unchanged',request_id)
            return Result(body,signature,False)
        new_signature=resign_if_verified(body,rewritten,unique,material,signature)
        if new_signature is None:
            return Result(body,signature,False)
        self.journal.record('request_rewritten',request_id,input_bytes=len(body),output_bytes=len(rewritten),target_version=self.protocol.target_version)
        return Result(rewritten,new_signature,True)
