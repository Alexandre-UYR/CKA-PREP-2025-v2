# Question: The Job that will never finish
#
# The Job `import` in the `jobs` namespace keeps failing and is heading for
# the Error state.
#
# Task:
# 1. Find out why it fails. `kubectl get job` tells you it failed and how
#    many of its pods failed; the reason is in the pods themselves.
# 2. Fix it and get the Job to COMPLETE, with all three of its completions
#    succeeded.
# 3. A Job's pod template is IMMUTABLE, so you will have to replace the Job.
#    Keep the same name, keep the same completion count, and do not raise
#    backoffLimit above 2.
#
# When you are done:
#   kubectl -n jobs get job import
# must show COMPLETIONS 3/3 and a status of Complete, and the Job's pods
# must be Succeeded rather than Failed.
