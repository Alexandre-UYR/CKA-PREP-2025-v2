# Question: Ten of them, five at a time
#
# The Job `import` in the `jobs` namespace ran once with the default settings:
# one completion, one at a time.
#
# Task:
# Replace it with a Job that has a `backoffLimit` set, `completions: 10` and
# `parallelism: 5`, running the same container.
#
# It has to reach all ten successful completions - `kubectl -n jobs get job
# import` must show COMPLETIONS 10/10 and a status of Complete.
#
# The Job keeps its name and its container. Nothing else in the cluster should
# be touched.
