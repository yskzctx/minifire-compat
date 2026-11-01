"""Check an actual local client binary, without reading account traffic."""
from pathlib import Path

from proxy_offline.signing_inspect import inspect_signing_input


ROOT = Path(__file__).resolve().parents[2] / "work/apk-files"


def test_static_login_input_is_tied_to_known_client_binary():
    result = inspect_signing_input(
        ROOT / "lib/arm64-v8a/libil2cpp.so",
        ROOT / "assets/bin/Data/Managed/Metadata/global-metadata.dat",
        0x1DBBE70,
        0x1DBBE78,
    )
    assert result["sign_method_rva"] == "0x1dbbb48"
    assert result["literal_length"] == 16
    assert result["literal_sha256"] == "7ae28f2f44dcfe16e83b9de24e02593199710fb309dffe0136902aa431949b24"
    assert result["client_sha256"] == "6d86ac671d3136a79a6e486c3e547660d0dfbd13160169f35d86c5bfdc479e5d"
