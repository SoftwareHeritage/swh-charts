# Software Heritage stack helm chart
## Unit tests

The test are done with [helm-unittest](https://github.com/quintush/helm-unittest)

helm-unit can be launched in docker or used as a [helm plugin](https://github.com/quintush/helm-unittest#install).


For a run in docker, run this command:

```
docker run -ti --rm -v $(pwd)/..:/apps quintush/helm-unittest:3.11.1-0.3.0  --color --debug swh
```

warning: It tests the helm chart behavior, not the descriptors are valid for kubernetes

Example of outputs:
```
docker run -ti --rm -v $(pwd)/..:/apps quintush/helm-unittest:3.11.1-0.3.0  --color --debug swh

### Chart [ Argocd applications commonly used in to configure a SWH cluster ] .

 PASS  test cluster configuration application   tests/basic-applications_test.yaml
 PASS  test cluster metallb application tests/metallb-application_test.yaml


### Chart [ swh ] swh

 PASS  test graphql deployment  swh/tests/graphql_configmap_test.yaml
 PASS  test graphql deployment  swh/tests/graphql_deployment_test.yaml
 PASS  test graphql deployment  swh/tests/graphql_global_test.yaml
 PASS  test graphql deployment  swh/tests/graphql_service_test.yaml

Charts:      1 passed, 1 total
Test Suites: 4 passed, 4 total
Tests:       9 passed, 9 total
Snapshot:    0 passed, 0 total
Time:        29.410877ms
```

## Helm differences

To ensure a change does not generate unexpected changes, the `test.sh` script allow to
generate and compare the helm output for all the different values files in the `values`
directory. The comparison is made between the outputs based on the production branch and
the current branch.

Ideally, if not too long, the output of this script should be pasted on the MRs to
simplify the reviews.

Example:
```
$ cd swh-charts/swh
$ git checkout branch-dev
$ ./helm-diff.sh
Comparing changes between branches production and branch-dev...
Switched to branch 'production'
Your branch is up to date with 'origin/production'.
Generate config in production branch for values/default.yaml...
Generate config in production branch for values/production-cassandra.yaml...
Generate config in production branch for values/production.yaml...
Generate config in production branch for values/staging-cassandra.yaml...
Generate config in production branch for values/staging.yaml...
Switched to branch 'branch-dev'
Your branch is up to date with 'origin/branch-dev'.
Generate config in branch-dev branch for values/default.yaml...
Generate config in branch-dev branch for values/production-cassandra.yaml...
Generate config in branch-dev branch for values/production.yaml...
Generate config in branch-dev branch for values/staging-cassandra.yaml...
Generate config in branch-dev branch for values/staging.yaml...


------------- diff for values/production-cassandra.yaml -------------

No differences


------------- diff for values/production.yaml -------------

No differences


------------- diff for values/staging-cassandra.yaml -------------

No differences


------------- diff for values/staging.yaml -------------

--- /tmp/staging.yaml.before    2023-06-07 19:24:21.110590131 +0200
+++ /tmp/staging.yaml.after     2023-06-07 19:24:21.646591990 +0200
@@ -3938,20 +3938,21 @@
           directory: 100
           directory_entries: 500
           extid: 100
           release: 100
           release_bytes: 52428800
           revision: 100
           revision_bytes: 52428800
           revision_parents: 200
       - cls: filter
       - cls: retry
+      - cls: record_references
       - cls: postgresql
         db: host=db1.internal.staging.swh.network port=5432 user=swh dbname=swh password=${POSTGRESQL_PASSWORD}
         objstorage:
           cls: noop

     journal_client:
       cls: kafka
       brokers:
         - journal1.internal.staging.swh.network:9094
       sasl.username: swh-postgresql-stg
...
```
