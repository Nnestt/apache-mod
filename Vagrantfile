# -*- mode: ruby -*-
# vi: set ft=ruby :
# ============================================================
# CVE-2026-63686 — Vagrant PoC Environment
# ============================================================
# Cross-platform: works on Windows (VirtualBox) and macOS (VMware Fusion).
#
# Windows:  vagrant up                          (uses VirtualBox)
# macOS:    vagrant up --provider=vmware_desktop (uses VMware Fusion)
#
# After VM is up:
#   python3 attacker/poison.py --port 9090   # start attacker
#   curl http://localhost:8080/              # fire exploit
#   vagrant ssh -c "sudo tail /var/log/apache2/error.log"  # check crash
#
# Other commands:
#   vagrant ssh             # SSH into the target VM
#   vagrant halt            # shut down the VM
#   vagrant destroy -f      # delete the VM entirely
#   vagrant up --provision  # re-run the setup script
# ============================================================

Vagrant.configure("2") do |config|

  # ── Base box ──────────────────────────────────────────────
  # bento boxes support VirtualBox (amd64) and VMware (amd64 + arm64)
  config.vm.box = "bento/debian-12"
  config.vm.hostname = "target"

  # ── Network ───────────────────────────────────────────────
  # Port forward: host:8080 → VM:80
  # Inside the VM, the host is reachable at:
  #   - 10.0.2.2     (VirtualBox NAT gateway)
  #   - 172.16.x.1   (VMware NAT gateway — setup.sh detects this)
  config.vm.network "forwarded_port", guest: 80, host: 8080

  # ── VirtualBox (Windows / Intel Mac) ──────────────────────
  config.vm.provider "virtualbox" do |vb|
    vb.name   = "CVE-2026-63686-Target"
    vb.memory = 1024
    vb.cpus   = 1
    vb.gui    = false
  end

  # ── VMware Fusion / Workstation (macOS Apple Silicon) ─────
  config.vm.provider "vmware_desktop" do |vmw|
    vmw.vmx["displayName"]  = "CVE-2026-63686-Target"
    vmw.vmx["memsize"]      = "1024"
    vmw.vmx["numvcpus"]     = "1"
    vmw.gui                 = false
    vmw.allowlist_verified  = true
  end

  # ── Provisioning ──────────────────────────────────────────
  config.vm.provision "shell",
    path: "target/setup.sh",
    env:  { "VAGRANT" => "1" }

end
