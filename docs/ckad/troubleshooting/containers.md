# Container Image Basics

**Curriculum domain:** Application Design and Build (20%, defining, building and modifying container images)

---

## Scenario 1: Build & Push Custom Image

**Task:** Build a Python app image, push to registry, deploy in Kubernetes.

### Step 1: Write Dockerfile

```dockerfile
# Dockerfile
FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app.py .

CMD ["python", "app.py"]
```

### Step 2: Build Image

```bash
# Build
docker build -t myregistry.io/python-app:1.0 .

# Or with Podman (if no Docker)
podman build -t myregistry.io/python-app:1.0 .

# Verify
docker images
```

### Step 3: Push to Registry

```bash
# Login  (if private registry)
docker login myregistry.io

# Push
docker push myregistry.io/python-app:1.0

# Verify image exists
docker image inspect myregistry.io/python-app:1.0
```

### Step 4: Use in Kubernetes

```bash
# Create deployment with custom image
kubectl create deployment myapp \
  --image=myregistry.io/python-app:1.0

# If private registry, add ImagePullSecret
kubectl create secret docker-registry regcred \
  --docker-server=myregistry.io \
  --docker-username=<user> \
  --docker-password=<pass> \
  --docker-email=<email>

# And reference in deployment:
# spec.template.spec.imagePullSecrets:
#   - name: regcred
```

---

## Scenario 2: Load Image from Local TAR (Offline)

**Task:** Build image, export to tar, load in K8s cluster without registry.

```bash
# 1. Build image
docker build -t my-offline-app:1.0 .

# 2. Export to tar
docker save my-offline-app:1.0 -o app.tar

# 3. Transfer tar file to K8s cluster /tmp/app.tar

# 4. Load into cluster
docker load -i app.tar

# Or with Podman:
podman load -i app.tar

# 5. Use in deployment  
kubectl create deployment offline-app --image=my-offline-app:1.0 --image-pull-policy=Never
# Note: imagePullPolicy: Never (don't pull, use local)
```

---

## Scenario 3: Multi-Stage Build (Smaller Image)

**Task:** Reduce image size using multi-stage build.

```dockerfile
# Build stage
FROM python:3.9-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install -r requirements.txt --target /build/lib

# Runtime stage (smaller!)
FROM python:3.9-slim
WORKDIR /app
COPY --from=builder /build/lib /app/lib
COPY app.py .
CMD ["python", "-c", "import sys; sys.path.insert(0, '/app/lib'); exec(open('app.py').read())"]
```

**Advantage:** Final image only contains runtime stage (smaller, faster pulls).

---

## Image Best Practices

- Use specific tags (`nginx:1.19`) NOT `latest`
- Use slim/alpine bases to reduce size (`python:3.9-slim`)
- Layer caching: Dockerfile statements that change rarely go first
- Don't run as root (security)
- Use .dockerignore to exclude unnecessary files

---

## Exam Reality

Container building is **rarely** tested in CKAD (maybe 1-2 questions max).  
More common: "Deploy this image" (using existing images).

Focus: Image selection, pull secrets, imagePullPolicy.

