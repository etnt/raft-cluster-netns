# Generate load for a HA cluster

The `foo` package contains a very simple service template
that doesn't involve any devices. It just populates config
data of the `bar` model via a template from the "top" model: `foo`.

The idea is to be able to study how a HA (Raft) cluster behaves
during traffic load, especially in combination with various
impairment scenarios (see the raft-cluster-netns.sh script).

## Usage

To compile the package:

```bash
make -C src
```

Setup a link to this package for every NSO node involved.
Assume a cluster of 7 nodes, where we have this directory structure:

```bash
├── packages
│   └── foo
└── work_dir
    ├── ncs-run1
    ├── ncs-run2
    ├── ncs-run3
    ├── ncs-run4
    ├── ncs-run5
    ├── ncs-run6
    └── ncs-run7
```

Run the command:

```bash
for i in `seq 1 7`; do (cd work_dir/ncs-run${i}/packages; ln -s ../../../packages/foo;) done
```

Make sure to load the new package:

```bash
# Assuming node 5 is the leader of the cluster
./raft-cluster-netns.sh exec 5 "ncs_cli -u admin"

admin@ncs> request packages reload
...
reload-result {
    package foo
    result true
}
...
```

Create instance data for the `foo` model to be loaded:

```bash
# Create a dir where to store the config data to be loaded
cd packages/foo
mkdir foo-data
cd foo-data

# Create N number of files containing config data to be loaded
# Here N = 1000
for i in `seq 1 1000`; do sed "s/bill/bill$i/" ../foo.xml > foo$i.xml; done
```

Assume we have started our cluster and that node 7 is the leader:

```bash
# Enter the NetNS of node 7
./raft-cluster-netns.sh shell 7

# Load all the config
cd ../../packages/foo/foo-data
ls | xargs -P 10 -L 1 ncs_load -lm
```

Loading all this data will now create lots of commits that are replicated
among the members in the cluster.

Use for example the CLI command: `show ha-raft` to study the behaviour of the cluster.
