heat-viz
========

GraphViz depiction of Heat dependencies.

Run with EG `ruby heat-viz.rb ../tripleo-heat-templates/overcloud.yaml` then browse heat-deps.yaml.

The diagram is produced dynamically with viz.js (https://github.com/mdaines/viz.js/).

Both CFN and HOT format are handled but the dependency detection is very simple. It does not handle resource groups or autoscaling at all.
