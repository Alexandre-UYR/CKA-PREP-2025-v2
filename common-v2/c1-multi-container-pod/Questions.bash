# Question: Multi-container Pod
#
# Task:
# In the multicontainer namespace, create a Pod named cache with two containers:
#   - a container named redis, using the image redis:7
#   - a container named memcached, using the image memcached
# Both containers must be running and ready at the same time.
#
# Verify that the redis container actually answers: exec into it and run
# `redis-cli ping` - it must reply PONG.
