# Example config of gobgpd

## Addresses and ASNs

### manager

AS: 64514

Router-ID: 172.17.0.2

Interfaces:

172.17.0.2/16 (bridge)

192.168.30.2/24 (to berlin)

192.168.31.2/24 (to london)

192.168.32.2/24 (to paris)

### berlin

AS: 64513

Router-ID: 192.168.30.97

Interfaces:

192.168.30.97/32 (loopback)

192.168.30.97/24 (connected to manager)

### london

AS: 64512

Router-ID: 192.168.31.98

Interfaces:

192.168.31.98/32 (loopback)

192.168.31.98/24 (connected to manager)

### paris

AS: 64511

Router-ID: 192.168.32.99

Interfaces:

192.168.32.99/32 (loopback)

192.168.32.99/24 (connected to manager)

## Static Routes

Each edge router (berlin, london, paris) must know how to reach the manager’s
loopback, and the manager must know how to reach each edge’s loopback.

Example (berlin):

```
ip route add 172.17.0.2 via 192.168.30.2
```

Manager:

```
ip route add 192.168.30.97 via 192.168.30.97
ip route add 192.168.31.98 via 192.168.31.98
ip route add 192.168.32.99 via 192.168.32.99
```

(check with ping for direct reachability)

## GoBGP Configs

### Manager (/etc/gobgp/manager.yaml)

```
global:
  config:
    as: 64514
    router-id: 172.17.0.2

neighbors:
  - config:
      neighbor-address: 192.168.30.97
      peer-as: 64513
    transport:
      config:
        local-address: 172.17.0.2
  - config:
      neighbor-address: 192.168.31.98
      peer-as: 64512
    transport:
      config:
        local-address: 172.17.0.2
  - config:
      neighbor-address: 192.168.32.99
      peer-as: 64511
    transport:
      config:
        local-address: 172.17.0.2
```

### Berlin (/etc/gobgp/berlin.yaml)

```
global:
  config:
    as: 64513
    router-id: 192.168.30.97

neighbors:
  - config:
      neighbor-address: 172.17.0.2
      peer-as: 64514
    transport:
      config:
        local-address: 192.168.30.97
```

### London (/etc/gobgp/london.yaml)

```
global:
  config:
    as: 64512
    router-id: 192.168.31.98

neighbors:
  - config:
      neighbor-address: 172.17.0.2
      peer-as: 64514
    transport:
      config:
        local-address: 192.168.31.98
```

### Paris (/etc/gobgp/paris.yaml)

```
global:
  config:
    as: 64511
    router-id: 192.168.32.99

neighbors:
  - config:
      neighbor-address: 172.17.0.2
      peer-as: 64514
    transport:
      config:
        local-address: 192.168.32.99
```

## Run

In each namespace/container:

gobgpd -f /etc/gobgp/<node>.yaml -l debug


Check neighbor states:

gobgp neighbor


Advertise a test prefix (say, from berlin):

gobgp global rib add 10.100.13.0/24


It should show up in manager’s RIB, and then can be redistributed
further if you like.
