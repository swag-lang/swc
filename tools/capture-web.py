"""Record a local browser video with system sound, then verify native editor playback.

Requires Windows, an interactive desktop, and Chrome. The browser uses an owned
temporary profile. No personal browser session or Capture library is used. Evidence is kept
outside the checkout. This drives production handlers in a native application integration
test; it does not test external mouse hit testing against the shipped executable.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


PAGE = r"""<!doctype html><title>Swag Capture Web AV Probe</title>
<style>body{margin:0;background:#16181b;color:white;font:16px sans-serif}
video{display:block;margin:20px;width:320px;height:180px}p{margin:20px}</style>
<video autoplay loop playsinline></video><p>Swag Capture — browser video + 440 Hz audio</p>
<script>
(async()=>{
 const video=document.querySelector('video');video.src='/fixture.webm';await video.play();
 setInterval(async()=>{
  const control=await(await fetch('/control')).json();if(control.mute){video.pause();video.muted=true;}
  const r=video.getBoundingClientRect(),border=(outerWidth-innerWidth)/2;
  await fetch('/status',{method:'POST',body:JSON.stringify({playing:!video.paused,muted:video.muted,
   time:video.currentTime,ready:video.readyState,width:video.videoWidth,height:video.videoHeight,
   insetX:Math.round((border+r.x)*devicePixelRatio),
   insetY:Math.round((outerHeight-innerHeight-border+r.y)*devicePixelRatio)})});
 },100);
})().catch(e=>fetch('/status',{method:'POST',body:JSON.stringify({error:String(e)})}));
</script>"""


def browser_path(explicit):
    if explicit:
        return Path(explicit).resolve(strict=True)
    for base in ('PROGRAMFILES', 'PROGRAMFILES(X86)', 'LOCALAPPDATA'):
        candidate = Path(os.environ.get(base, '')) / 'Google/Chrome/Application/chrome.exe'
        if candidate.is_file():
            return candidate
    raise RuntimeError('Chrome was not found; pass --browser <Chrome executable>')


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--browser')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--width', type=int, default=320)
    parser.add_argument('--height', type=int, default=180)
    parser.add_argument('--devmode-compiler', action='store_true',
                        help='drive the Release application with swc.dm.exe')
    args = parser.parse_args()
    if args.width < 2 or args.height < 2 or args.width % 2 or args.height % 2:
        parser.error('capture dimensions must be positive even pixel counts')
    if sys.platform != 'win32':
        parser.error('this integration scenario requires Windows WASAPI loopback')
    repo = Path(__file__).resolve().parent.parent
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='capture-web-'))
    if output == repo or repo in output.parents:
        parser.error('--output must be outside the checkout')
    output.mkdir(parents=True, exist_ok=True)
    sandbox = output / 'sandbox'
    if sandbox.exists():
        parser.error('--output already contains a sandbox; choose a fresh evidence directory')
    sandbox.mkdir()
    status = {}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            if self.path == '/fixture.webm':
                data = (repo / 'bin/apps/modules/swagcapture/src/tests/datas/webcapture.webm').read_bytes()
                content_type = 'video/webm'
            elif self.path == '/control':
                data = json.dumps({'mute': (sandbox / 'mute-source').exists()}).encode()
                content_type = 'application/json'
            else:
                data = PAGE.replace('width:320px;height:180px',
                                    f'width:{args.width}px;height:{args.height}px').encode()
                content_type = 'text/html'
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_POST(self):
            data = self.rfile.read(int(self.headers['Content-Length']))
            status.update(json.loads(data))
            (output / 'browser.json').write_text(json.dumps(status, indent=2))
            if status.get('muted') and not status.get('playing'):
                (sandbox / 'source-silent').touch()
            self.send_response(204)
            self.end_headers()

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    # Each browser instance has its own profile, so termination cannot reach a personal session.
    profile = Path(tempfile.mkdtemp(prefix='browser-profile-', dir=output))
    browser = subprocess.Popen([str(browser_path(args.browser)),
        f'--user-data-dir={profile}', '--no-first-run', '--no-default-browser-check',
        '--autoplay-policy=no-user-gesture-required', '--force-device-scale-factor=1',
        '--disable-background-timer-throttling', '--disable-renderer-backgrounding',
        '--disable-backgrounding-occluded-windows',
        '--window-position=100,80', f'--window-size={max(600, args.width + 80)},{max(500, args.height + 150)}',
        f'--app=http://127.0.0.1:{server.server_port}/'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + 25
        while not (status.get('playing') and status.get('ready', 0) >= 3 and status.get('time', 0) > .2):
            if status.get('error'):
                raise RuntimeError(status['error'])
            if time.monotonic() > deadline:
                raise RuntimeError(f'browser video did not become ready: {status}')
            time.sleep(.1)
        command = [sys.executable, str(repo / 'tools/tool.py'), 'apps']
        if args.devmode_compiler:
            command.append('dm')
        command += ['test', 'swagcapture',
                   '-bc', 'release', '--test-file', 'webcapture.win32.swg',
                   '--test-tag', 'integration.capture.web', '--run-timeout', '60',
                   '--run-arg', f'swag.sandbox={sandbox}',
                   '--run-arg', 'swag.audio.native-output=true',
                   '--run-arg', 'swag.capture.native-screen=true']
        environment = dict(os.environ, SWAG_CAPTURE_WEB_INSET_X=str(status['insetX']),
                           SWAG_CAPTURE_WEB_INSET_Y=str(status['insetY']),
                           SWAG_CAPTURE_WEB_WIDTH=str(args.width), SWAG_CAPTURE_WEB_HEIGHT=str(args.height))
        print(f'Browser ready: {status}\nEvidence: {output}', flush=True)
        # Admission is repeated by this explicit host runner immediately before compiling/testing.
        check = repo / '.agents/skills/modify-swag-codebase/scripts/check-machine-load.ps1'
        result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(check)], cwd=repo)
        if result.returncode:
            return result.returncode
        with (output / 'test.log').open('w', encoding='utf-8') as log:
            result = subprocess.run(command, cwd=repo, env=environment, stdout=log, stderr=subprocess.STDOUT)
        print((output / 'test.log').read_text(encoding='utf-8'), flush=True)
        if not result.returncode and not (sandbox / 'passed').exists():
            raise RuntimeError('the native scenario did not produce its completion checkpoint')
        return result.returncode
    finally:
        if browser.poll() is None:
            subprocess.run(['taskkill', '/PID', str(browser.pid), '/T', '/F'],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           creationflags=subprocess.CREATE_NO_WINDOW)
        browser.wait(timeout=10)
        shutil.rmtree(profile, ignore_errors=True)
        server.shutdown()


if __name__ == '__main__':
    raise SystemExit(main())
