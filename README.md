# RDP certificate scripts

These scripts obtain a publicly trusted Let's Encrypt certificate using a
Cloudflare DNS challenge, package it as a PFX, and bind it to the Windows RDP
listener.

## Run directly on an Oracle VPS

Replace the hostname and email address, then run:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/qy2009/RDP-certificate/main/01-issue-rdp-certificate.sh) win.rui-qiu.com you@example.com
```

The script prompts for the Cloudflare API token and PFX password. Neither
secret is stored in this repository or included in the command line.

## Before starting

1. Create a Cloudflare API token limited to the relevant zone. Give it:
   `Zone / Zone / Read` and `Zone / DNS / Edit`.
2. On a Linux machine with Docker and OpenSSL (for example, the Oracle VPS),
   make script 01 executable:

   ```sh
   chmod +x 01-issue-rdp-certificate.sh
   ```

3. Issue the certificate. Use the exact DNS name entered by RDP clients:

   ```sh
   ./01-issue-rdp-certificate.sh win.rui-qiu.com you@example.com
   ```

4. Copy both resulting files to the Windows machine:

   - `win.rui-qiu.com.pfx`
   - `win.rui-qiu.com.sha1`

5. Open **Command Prompt as Administrator** on Windows and run:

   ```bat
   02-import-bind-rdp-certificate.cmd C:\path\win.rui-qiu.com.pfx
   ```

6. Reboot Windows, then connect using the same hostname on the certificate.

## Windows 7 and Windows 11 compatibility

The generation script runs on Linux, not Windows. The import/bind script is
designed for both Windows 7 and Windows 11:

- Windows 7 normally uses its built-in WMIC Terminal Services provider, so it
  does not require PowerShell.
- Windows 11 uses WMIC when present and Windows PowerShell as a fallback.
- The certificate uses RSA-2048 for compatibility with older RDP hosts.

Each machine should normally have its own certificate matching the unique DNS
hostname used to reach it. Run script 01 once for each hostname, then copy that
host's PFX and SHA-1 file to the corresponding Windows machine.

Windows 7 must still have current SHA-2/root-certificate updates and TLS 1.2
support. A valid certificate does not add TLS 1.2 by itself.

If Windows 7 binds the certificate but RDP cannot read its private key, open
`certlm.msc`, go to Personal > Certificates, right-click the new certificate,
choose All Tasks > Manage Private Keys, and grant `NETWORK SERVICE` Read access.
Microsoft specifically documents this permission for Windows 7 RDP host keys.

## Renewal

Let's Encrypt certificates are short-lived. Run script 01 again periodically;
it reuses its `lego-state` directory and renews when appropriate. After renewal,
copy the new PFX and SHA-1 files to Windows, run script 02 again, and reboot.

Do not publish the PFX, its password, the Cloudflare token, or the `lego-state`
directory. The PFX contains the private key.

## Security note

Changing RDP from port 3389 to port 443 does not make raw RDP safe to expose to
the internet. Prefer a VPN such as WireGuard/Tailscale or a properly configured
Remote Desktop Gateway, and require strong unique credentials and account
lockout protection.
