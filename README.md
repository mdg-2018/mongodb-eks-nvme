# Using local NVMe disks for your MongoDB deployment in EKS
This is a guide for how to take advantage of cheap and fast storage for your MongoDB cluster running in EKS. Before we get into the details I have a few disclaimers.
1. These disks are ephemeral and using them for database storage increases your risk of data loss.
2. This is not an official MongoDB guide but rather an example of one way to go about taking advantage of this storage type.

# Configuring your nodes in AWS
For my test environment I deployed three m5d.large nodes (2cpu/8gb ram). These instances come with local ephemeral nvme storage. Because I only had the three nodes I mounted the storage manually, but if this were used frequently this should be managed in a launch template or other automated process.
```shell
sudo mkfs.xfs /dev/nvme1n1 # Create the xfs filesystem for MongoDB

# Create the directory for the Rancher local-path-provisioner (more on this later) and mount the ephemeral storage
sudo mkdir -p /opt/local-path-provisioner 
sudo mount /dev/nvme1n1 /opt/local-path-provisioner

# Update /etc/fstab so that ephemeral storage is mounted on reboot
echo "/dev/nvme1n1 /opt/local-path-provisioner xfs defaults 0 0" | sudo tee -a /etc/fstab
```

# Configuring a local path provisioner in your EKS cluster
There are a couple choices for taking advantage of a local path for storage in Kubernetes. For this guide I've chosen Rancher's [local-path-provisioner](https://github.com/rancher/local-path-provisioner), but that's mostly because I'm more familiar with this tool. The other likely option would be the [sig-storage-local-static-provisioner](https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner/tree/master).

After following Rancher's instructions for installing the local-path-provisioner, I made sure my drive was mounted at the default path from the provisioner install. This path is defined in the configmap below. The path can of course be changed if you want to mount your nvme drive somewhere else.

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: local-path-config
  namespace: local-path-storage
data:
  config.json: |-
    {
            "nodePathMap":[
            {
                    "node":"DEFAULT_PATH_FOR_NON_LISTED_NODES",
                    "paths":["/opt/local-path-provisioner"]
            }
            ]
    }
  setup: |-
    #!/bin/sh
    set -eu
    mkdir -m 0777 -p "$VOL_DIR"
  teardown: |-
    #!/bin/sh
    set -eu
    rm -rf "$VOL_DIR"
  helperPod.yaml: |-
    apiVersion: v1
    kind: Pod
    metadata:
      name: helper-pod
    spec:
      priorityClassName: system-node-critical
      tolerations:
        - key: node.kubernetes.io/disk-pressure
          operator: Exists
          effect: NoSchedule
      containers:
      - name: helper-pod
        image: docker.io/library/busybox
        imagePullPolicy: IfNotPresent

```

# Configuring MongoDB
Finally, for my MongoDB replica set I configured spec.podSpec.persistence.single.storageClass to use the local-path storage class from the Rancher local-path-provisioner. After spinning up the replica set I was able to see the data from the resulting PVC in /opt/local-path-provisioner on the nodes I deployed.


```yaml
apiVersion: mongodb.com/v1
kind: MongoDB
metadata:
  name: storage-test
  namespace: mongodb
spec:
  type: ReplicaSet
  members: 3
  version: "9.0.4"
  persistent: true
  opsManager:
    configMapRef:
      name: eks-test-cm
  credentials: eks-test-organization-secret
  security:
    authentication:
      enabled: true
      modes: ["SCRAM"]
  podSpec:
    persistence:
      single:
        storage: 10Gi
        storageClass: local-path
```

# Conclusion
Using ephemeral NVMe drives is a cost effective way to vastly increase your I/O throughput in AWS. Just be sure you're prepared to accept the risks that come with using this storage type! Be sure to review which [conditions cause instance store volumes to be deleted](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-store-lifetime.html). And finally, be sure you regularly test your backups!