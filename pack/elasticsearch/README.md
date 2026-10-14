# Service reliability — Elasticsearch

Three strict-mapped indices: requests, deployments, incidents. Includes staging/production, errors, latency, trace IDs, deployment correlation, coordinates and unresolved incidents. Percentile results are approximate; use tolerances, not exact equality, for percentile tests.

Set PACK_ELASTICSEARCH_URL; optionally PACK_ELASTICSEARCH_API_KEY and PACK_ELASTICSEARCH_CA_CERT. TLS verification remains enabled. All resources use the `qw-complex-reliability-` prefix.

```sh
python -m tools.elastic_runner migrate --target 1 --allow-write
python -m tools.elastic_runner seed --scale 1 --allow-write
python -m tools.elastic_runner migrate --target 2 --allow-write
python -m tools.elastic_runner verify --scale 1
```

Pause all writers and run one migration operator. V2 creates a new requests index, synchronously reindexes with latency_seconds conversion, checks reindex errors, counts and every migrated document, then switches the read alias in one aliases request. The old index is preserved. Deployments/incidents remain v1. A failed v2 destination is deliberately not overwritten on retry. Inspect the reindex task/state, repair or remove only the dedicated failed destination, and retry after review. There is no live dual-write or CDC catch-up.

The verification scans all documents, compares exact fixtures and verifies alias ownership. This is deliberately a small lab validation, not an efficient billion-document reconciliation. Replica count 0 and one shard are local-lab settings, not production recommendations.

Rollback: pause writers, validate old index, atomically remove the requests alias from v2 and add it to v1. New v2-only writes would be lost from the read view; reconcile first. No index is deleted automatically.

analytics.json can be used as a search request against the requests alias. Querywise v5 uses restricted ES|QL plans and concrete index registration. Native percentile/full-text/nested/cross-index requests here exceed its current UI capabilities. Map latitude/longitude into scalar serving fields if your Querywise mapping discovery cannot expose geo_point fields.
