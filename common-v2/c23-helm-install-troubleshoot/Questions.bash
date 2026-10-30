# Question: Install a chart and fix it when it fails
#
# Task:
# Install the chart at /tmp/cka-lab/charts/broken-chart as release `broken`
# into namespace `webapps`.
#
# The release installs, but its pod never becomes ready. Find the fault, fix
# the chart, and get the release to a healthy state:
#   - `helm list -n webapps` must show the release `broken` with STATUS deployed
#   - `helm status broken -n webapps` must succeed
#   - the Deployment the chart creates must have 1 ready replica and its pods
#     must be Running
#
# The chart is on disk at /tmp/cka-lab/charts/broken-chart. Remember that
# editing the files on disk does not change a release that is already
# installed: the change reaches the cluster on the next `helm upgrade`.
