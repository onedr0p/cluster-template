# velero

## Install Velero command line

```sh
brew install velero
```

## Usage

![](https://i.imgur.com/feo6EpE.png)

[Velero](https://velero.io/) is a cluster backup & restore solution.  I can also leverage restic to backup persistent volumes to S3 storage buckets.

* [velero](velero/)
* [rules/velero.yaml](rules/velero.yaml) - Prometheus alertmanager rules for Velero
* [change-storage-class-config.yaml](change-storage-class-config.yaml) - (disabled) example ConfigMap demonstrating how to restore from one storage class type to a different storage class type

## Restore Process

In order to restore a given workload, the follow steps should work:

1. A backup should already be created either via:
   * a global backup (e.g. a scheduled backup),
   * or via a backup created using a label selector (that's present on the deployment, pv, & pvc) for the application, e.g. `velero backup create test-minecraft --selector "app=mc-test-minecraft" --wait`
1. <Do whatever action results in the active data getting lost (e.g. `kubectl delete hr mc-test`)>
1. Delete the unwanted new data & associate Deployment/StatefulSet/Daemonset, e.g. `kubectl delete deployment mc-test-minecraft && kubectl delete pvc mc-test-minecraft-datadir`
1. Restore from restic the backup with only the label selector, e.g. `velero restore create --from-backup test-minecraft --selector "app=mc-test-minecraft" --wait`

* This should not interfere with the HelmRelease or require scaling helm-operator
* You don't need to worry about adding labels to the HelmRelease or backing-up the helm secret object
