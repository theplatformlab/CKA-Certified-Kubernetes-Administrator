# Two broken Deployments

**Context:** `kubectl config use-context {{CONTEXT}}`

Namespace `checkout` runs two Deployments, `cart` and `payment`. Neither of them has a ready pod.

Fix both:

1. `cart` must run nginx 1.28 in its Alpine variant with 2 ready replicas.
2. `payment` must run with 2 ready replicas without restarts. Keep its image, its command and its other settings.

## Hints

- `k -n checkout get pods` shows two different failure states. `describe` the one pod, read the `logs --previous` of the other.
- The cart image tag has a typo. `payment` exits with an error about a missing environment variable.
- Compare the variable the app wants with the variables the Deployment sets: `k -n checkout set env deploy/payment --list`.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n checkout get pods                     # cart: ImagePullBackOff, payment: CrashLoopBackOff
k -n checkout describe pod -l app=cart | grep -A2 Failed
# Failed to pull image "nginx:1.28-alpline": ... not found
k -n checkout set image deploy/cart cart=nginx:1.28-alpine

k -n checkout logs -l app=payment --previous
# FATAL: environment variable GATEWAY_URL is not set
k -n checkout set env deploy/payment --list
# GATEWAY_ULR=http://gateway.checkout.svc:9000      <- typo in the name
k -n checkout edit deploy payment         # rename GATEWAY_ULR to GATEWAY_URL
k -n checkout rollout status deploy/payment
k -n checkout rollout status deploy/cart
```

`kubectl set env deploy/payment GATEWAY_URL=...` works too, but leaves the misspelled variable behind (remove it with `GATEWAY_ULR-`). Both fixes change the pod template, so the Deployments roll out new pods, and the crashing old ones go away by themselves.
