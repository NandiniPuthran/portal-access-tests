# fb_http_receiver

Temporary HTTP(S) endpoint that receives Fluent Bit `http` output and writes it to
`/var/log/fb-receiver/fluentbit-YYYY-MM-DD.log`. It's meant as a stand-in until the real
monitoring proxy exists. It uses only the Python standard library and runs as a hardened
systemd service under a dedicated no-login user.

## Layout

```
install.yml / uninstall.yml           playbooks
inventory/hosts.ini                   [fb_receiver] group
inventory/group_vars/fb_receiver.yml  port, URI, TLS examples
roles/fb_http_receiver/
  tasks/main.yml       phase wiring + tags
  tasks/validate.yml   input/target/path-safety asserts (always runs)
  tasks/install.yml    python3, user, dirs, script, env file, retention, uninstall script
  tasks/tls.yml        cert/key/CA deploy, key-match + expiry checks; removes TLS when disabled
  tasks/service.yml    systemd unit, enable + start
  tasks/verify.yml     port, /healthz, unknown-URI 404
  tasks/uninstall.yml  full removal (state=absent)
```

## Usage

```bash
ansible-playbook install.yml --check --diff     # dry run
ansible-playbook install.yml
ansible-playbook install.yml --tags fb_receiver_tls     # only re-push certs
ansible-playbook install.yml --tags fb_receiver_verify  # only re-check

ansible-playbook uninstall.yml                              # keeps received logs
ansible-playbook uninstall.yml -e fb_receiver_purge_logs=true

# Without Ansible, on the host:
sudo /usr/local/sbin/fb-receiver-uninstall [--purge-logs]
```

Tags: `fb_receiver`, `fb_receiver_install`, `fb_receiver_tls`, `fb_receiver_service`,
`fb_receiver_verify`, `fb_receiver_uninstall`. Validation is tagged `always`.

## TLS

The role supports three modes:

| Mode  | Set |
|-------|-----|
| HTTP  | defaults |
| HTTPS | `fb_receiver_tls_enabled: true` + `fb_receiver_tls_cert_src` / `fb_receiver_tls_key_src` |
| mTLS  | the above + `fb_receiver_tls_client_ca_src` |

Cert sources are controller paths by default. Set `fb_receiver_tls_remote_src: true` if the
files already live on the target. Either way, the role copies them into `/etc/fb-receiver/tls`.
Setting TLS back to `false` removes that directory and restarts the service on plain HTTP.

`tls.verify on` in Fluent Bit checks the **receiver's** certificate. The cert must chain to
Fluent Bit's `tls.ca_file`, and its SAN must match `Host` (or `tls.vhost`). The role's local
verify step uses `validate_certs: false` against 127.0.0.1, so it confirms that TLS is being
served, not that the chain and SAN are right. Test that from a collector:

```bash
curl -sv --cacert ca.crt -d '{"t":1}' https://<receiver-name>:<port>/<uri>
```

## Notes

- No firewall rules are managed. Restrict the port to collector IPs at the host or network level.
- Ports below 1024 get `CAP_NET_BIND_SERVICE` automatically; the service still runs unprivileged.
- With `remote_src`, the role takes a copy of the cert. If something on the host renews the
  source cert, re-run `--tags fb_receiver_tls` to pick up the new one.
- Logs older than `fb_receiver_log_retention_days` are removed by `systemd-tmpfiles-clean.timer`.
  Set the value to `0` to disable cleanup.
- Uninstall leaves the `python3` package installed, because other things may depend on it.
