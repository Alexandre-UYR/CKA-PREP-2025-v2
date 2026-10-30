# Question: The rollout that can never move
#
# The Deployment `web` in the `rollout` namespace has been trying to roll out
# for ten minutes. The replica count has not changed and the new image is not
# running anywhere.
#
# Task:
# 1. Work out why the rollout cannot make any progress.
# 2. Fix it so that nginx:1.26 ends up running on all the replicas.
# 3. Do NOT delete the Deployment. Fix the Deployment that is already there.
#
# When you are done, all three replicas must be Running on nginx:1.26 and the
# Deployment's rollout must have been processed.
