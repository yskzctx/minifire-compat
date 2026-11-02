import hashlib
import json
from proxy_offline.adapter import SignedLoginAdapter, Journal
from proxy_offline.test_transform import protocol


def request():
    value=protocol.new('md.ApiLoginRequest')
    value.PhoneOs=1; value.ChannelID=23
    value.Version=value.VersionName='1.0.77'
    value.OpenToken='SYNTHETIC-PRIVATE-TOKEN'
    return value.SerializeToString()


def test_rewrite_resigns_and_records_stages_without_credentials(tmp_path):
    journal=Journal(tmp_path/'events.jsonl')
    adapter=SignedLoginAdapter(protocol,journal)
    body=request(); material=b'LOCAL-FIXTURE'; unique='LOCAL-TIME'
    signature=hashlib.sha1(body+material+unique.encode()).hexdigest().upper()
    result=adapter.terminal(body,unique,signature,material)
    assert result.changed
    assert protocol.parse('md.ApiLoginRequest',result.body).PhoneOs==2
    assert result.signature==hashlib.sha1(result.body+material+unique.encode()).hexdigest().upper()
    text=(tmp_path/'events.jsonl').read_text()
    events=[json.loads(line) for line in text.splitlines()]
    assert [event['event'] for event in events]==['signature_verified','request_rewritten']
    assert len({event['request_id'] for event in events})==1
    for secret in ('SYNTHETIC-PRIVATE-TOKEN',signature,unique,material.decode()):assert secret not in text


def test_signature_failure_passes_original_bytes_through(tmp_path):
    journal=Journal(tmp_path/'events.jsonl'); body=request()
    result=SignedLoginAdapter(protocol,journal).terminal(body,'time','0'*40,b'material')
    assert not result.changed and result.body==body and result.signature=='0'*40
    assert json.loads((tmp_path/'events.jsonl').read_text())['event']=='signature_unverified'


def test_journal_rejects_arbitrary_payload_fields(tmp_path):
    journal=Journal(tmp_path/'events.jsonl')
    try:journal.record('request_rewritten','request',token='private')
    except ValueError:pass
    else:raise AssertionError('credential fields must not be accepted')


def test_log_storage_failure_does_not_break_original_request(tmp_path):
    occupied=tmp_path/'not-a-directory'; occupied.write_text('fixture')
    journal=Journal(occupied/'events.jsonl'); body=request()
    result=SignedLoginAdapter(protocol,journal).terminal(body,'time','0'*40,b'material')
    assert result.body==body and not result.changed
    assert journal.last_error is not None
