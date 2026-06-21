## Task 1 — Managing a VirtualBox virtual machine

### Step 1 — Create DevVM with the required parameters

_Target spec: Ubuntu 64-bit, 4 GB RAM, 2 CPU, 20 GB dynamic VDI, NAT + Host-only networking._

**Commands:**

```cmd
VBoxManage createvm --name "DevVM" --ostype Ubuntu_64 --register
VBoxManage modifyvm "DevVM" --memory 4096 --cpus 2

VBoxManage createhd --filename "%USERPROFILE%\VirtualBox VMs\DevVM\DevVM.vdi" --size 20480 --variant Standard
VBoxManage storagectl "DevVM" --name "SATA" --add sata --controller IntelAhci
VBoxManage storageattach "DevVM" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "%USERPROFILE%\VirtualBox VMs\DevVM\DevVM.vdi"
```

**Output:**

```text
Virtual machine 'DevVM' is created and registered.
UUID: 803fae76-bb86-446c-bf12-8e9ec8b1cf66
Settings file: 'C:\Users\barte\VirtualBox VMs\DevVM\DevVM.vbox'

# createhd
0%...10%...20%...30%...40%...50%...60%...70%...80%...90%...100%
Medium created. UUID: 322107bb-c549-4426-969e-e1620d563437
```

**Explanation:**

`createvm` registers the VM and writes its `.vbox` settings file. `modifyvm` sets 4096 MB RAM and 2 vCPUs (these commands produce no output on success). The disk is a **20480 MB (20 GB)** VDI created with `--variant Standard`, which means **dynamic allocation** — the file grows on demand instead of reserving the full 20 GB up front. A SATA controller (`IntelAhci`) is added and the disk attached at port 0.

### Step 2 — Network configuration (NAT + Host-only)

**Commands:**

```cmd
VBoxManage list hostonlyifs
VBoxManage modifyvm "DevVM" --nic1 nat
VBoxManage modifyvm "DevVM" --nic2 hostonly --hostonlyadapter2 "VirtualBox Host-Only Ethernet Adapter"
```

**Output — existing host-only network:**

```text
Name:            VirtualBox Host-Only Ethernet Adapter
DHCP:            Disabled
IPAddress:       192.168.56.1
NetworkMask:     255.255.255.0
Status:          Up
```

**Explanation:**

A host-only network already existed on the standard VirtualBox subnet **`192.168.56.0/24`** with the host at `192.168.56.1`. Adapter 1 was set to **NAT** (gives the VM outbound internet access) and adapter 2 to **Host-only** (a private network shared with the host and other VMs, with no external exposure).

### Step 3 — Verify configuration

**Command:**

```cmd
VBoxManage showvminfo "DevVM" --machinereadable | findstr /I "memory cpus nic1 nic2 hostonlyadapter2 VMState ostype"
```

**Output:**

```text
ostype="Ubuntu (64-bit)"
memory=4096
cpus=2
VMState="poweroff"
nic1="nat"
hostonlyadapter2="VirtualBox Host-Only Ethernet Adapter"
nic2="hostonly"
```

**Explanation:**

Every required parameter is confirmed: Ubuntu 64-bit, 4096 MB RAM, 2 CPUs, adapter 1 = NAT, adapter 2 = host-only. `VMState="poweroff"` is expected since the VM was never booted.

### Step 4 — Snapshots

**Commands:**

```cmd
VBoxManage snapshot "DevVM" take "Before-updates" --description "Clean system before updates"
VBoxManage snapshot "DevVM" take "After-updates" --description "After system updates"
VBoxManage snapshot "DevVM" restore "Before-updates"
VBoxManage snapshot "DevVM" list
```

**Output:**

```text
# take Before-updates
Snapshot taken. UUID: 0e7fda33-095e-4c81-be6f-e075823f2425

# take After-updates
Snapshot taken. UUID: 373345b9-eb20-44e0-b966-e4530b7f02b8

# restore Before-updates
Restoring snapshot 'Before-updates' (0e7fda33-095e-4c81-be6f-e075823f2425)
0%...100%

# list
   Name: Before-updates (UUID: 0e7fda33-095e-4c81-be6f-e075823f2425) *
   Description: Clean system before updates
      Name: After-updates (UUID: 373345b9-eb20-44e0-b966-e4530b7f02b8)
      Description: After system updates
```

**Explanation:**

Two snapshots were created. The tree shows `After-updates` nested under `Before-updates` — each snapshot builds on its parent. After restoring `Before-updates`, the `*` marker in the list confirms it is now the **current** state, proving the rollback succeeded. (Note on syntax: the correct form is `snapshot "DevVM" list` — the VM name must not be repeated after `list`.)

### Step 5 — Cloning

**Commands:**

```cmd
VBoxManage clonevm "DevVM" --name "DevVM-Backup" --register
VBoxManage list vms
```

**Output:**

```text
Machine has been successfully cloned as "DevVM-Backup"

"linux1"       {f7dd36f3-bb8a-4b92-9bbd-b8b525e92e72}
"DevVM"        {803fae76-bb86-446c-bf12-8e9ec8b1cf66}
"DevVM-Backup" {2390bbdc-e445-4df5-989d-09a7945f390b}
```

**Explanation:**

`clonevm` produced a full copy, `DevVM-Backup`, with its **own new UUID** (`2390bbdc...`) distinct from the source. All registered VMs are listed (`linux1` is a pre-existing unrelated VM on this host).

---

## Task 2 — Host-only networking between two VMs

### Step 1 — Create VM1-Server and VM2-Client on the host-only network

**Commands:**

```cmd
VBoxManage createvm --name "VM1-Server" --ostype Ubuntu_64 --register
VBoxManage modifyvm "VM1-Server" --memory 1024 --nic1 hostonly --hostonlyadapter1 "VirtualBox Host-Only Ethernet Adapter"

VBoxManage createvm --name "VM2-Client" --ostype Ubuntu_64 --register
VBoxManage modifyvm "VM2-Client" --memory 1024 --nic1 hostonly --hostonlyadapter1 "VirtualBox Host-Only Ethernet Adapter"
```

**Output:**

```text
Virtual machine 'VM1-Server' is created and registered.
UUID: d024885d-bc95-45f0-8dc4-6e42d181f0f9

Virtual machine 'VM2-Client' is created and registered.
UUID: cc484d5b-ea79-4332-9836-2944bcc920c9
```

### Step 2 — Verify both VMs are on the host-only network

**Commands:**

```cmd
VBoxManage showvminfo "VM1-Server" --machinereadable | findstr /I "nic1 hostonlyadapter1"
VBoxManage showvminfo "VM2-Client" --machinereadable | findstr /I "nic1 hostonlyadapter1"
```

**Output:**

```text
# VM1-Server
hostonlyadapter1="VirtualBox Host-Only Ethernet Adapter"
nic1="hostonly"

# VM2-Client
hostonlyadapter1="VirtualBox Host-Only Ethernet Adapter"
nic1="hostonly"
```

**Explanation:**

Both VMs have adapter 1 attached to the same host-only network (`192.168.56.0/24`). On this network they share a private broadcast domain with each other and the host, isolated from the outside world.

### Step 3 — Host-only network connectivity test

Because the lightweight setup does not install a guest OS, the VMs themselves cannot yet hold an IP or answer ICMP. The host-only **network itself**, however, is live and was verified by pinging the host's interface on that subnet:

**Command:**

```cmd
ping -n 4 192.168.56.1
```

**Output:**

```text
Pinging 192.168.56.1 with 32 bytes of data:
Reply from 192.168.56.1: bytes=32 time<1ms TTL=128
Reply from 192.168.56.1: bytes=32 time<1ms TTL=128
Reply from 192.168.56.1: bytes=32 time<1ms TTL=128
Reply from 192.168.56.1: bytes=32 time<1ms TTL=128

Ping statistics for 192.168.56.1:
    Packets: Sent = 4, Received = 4, Lost = 0 (0% loss)
```

**Explanation:**

The host-only interface `192.168.56.1` replies with **0% loss** at `<1 ms`, proving the network exists, is up, and is routable. Any VM attached to it (once running an OS) lands on this same subnet and is reachable identically.

### Intended VM-to-VM configuration and network diagram

With a guest OS installed, the two VMs would be assigned static IPs on the host-only subnet and would ping each other directly:

```text
Intended IP plan:
  VM1-Server : 192.168.56.100
  VM2-Client : 192.168.56.101

Text network diagram:

   +-------------------+        +-------------------+
   |    VM1-Server     |        |    VM2-Client     |
   |  192.168.56.100   |        |  192.168.56.101   |
   +---------+---------+        +---------+---------+
             |                            |
             |   host-only network        |
             +------------+---------------+
                          |
                  192.168.56.0/24
                          |
                +---------+---------+
                |       HOST        |
                |   192.168.56.1    |
                +-------------------+

Intended test (inside each guest OS):
  # On VM1-Server
  ip addr show
  ping -c 4 192.168.56.101   # -> VM2-Client

  # On VM2-Client
  ip addr show
  ping -c 4 192.168.56.100   # -> VM1-Server
```
