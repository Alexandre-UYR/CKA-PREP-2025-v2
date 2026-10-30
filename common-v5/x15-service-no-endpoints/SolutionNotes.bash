# 1. Compare what the Service selects on with what the pods carry.
kubectl -n shop get svc cart-svc -o jsonpath='{.spec.selector}{"\n"}'
# map[app:cart]

kubectl -n shop get pods --show-labels
# NAME            READY   STATUS    RESTARTS   AGE   LABELS
# cart-7f9c8d4-2xk   1/1     Running   0          40s   app=cart-v2
# cart-7f9c8d4-hq4   1/1     Running   0          40s   app=cart-v2

# The Service selects app=cart. The pods carry app=cart-v2. Nothing matches.

kubectl -n shop get endpoints cart-svc
# NAME       ENDPOINTS   AGE
# cart-svc   <none>      50s

# 2. The fix is on the Service: point its selector at the labels the pods
#    actually carry. A merge patch changes the Service in place, so it keeps
#    its UID - nothing is deleted and re-created.
kubectl -n shop patch svc cart-svc --type=merge \
  -p '{"spec":{"selector":{"app":"cart-v2"}}}'

kubectl -n shop get svc cart-svc -o jsonpath='{.spec.selector}{"\n"}'
# map[app:cart-v2]

# 3. The endpoints controller fills the Endpoints object in a second or two.
kubectl -n shop get endpoints cart-svc
# NAME       ENDPOINTS                                AGE
# cart-svc   10.244.0.7:80,10.244.0.8:80             12s

kubectl -n shop get deploy cart
# NAME   READY   UP-TO-DATE   AVAILABLE   AGE
# cart   2/2     2            2           2m

# The other way out would have been to relabel the pods to app=cart, or to
# change the Deployment's template labels. The task rules that out: other
# things select on app=cart-v2.
