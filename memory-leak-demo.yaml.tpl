apiVersion: v1
kind: ServiceAccount
metadata:
  name: memory-leak-demo
  namespace: reliability-lab
# The demo needs no Kubernetes API or AWS access.
automountServiceAccountToken: false
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memory-leak-demo
  namespace: reliability-lab
  labels:
    app.kubernetes.io/name: memory-leak-demo
    app.kubernetes.io/part-of: ai-k8s-reliability-security-ops
    app.kubernetes.io/component: demo-workload
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: memory-leak-demo
  template:
    metadata:
      labels:
        app.kubernetes.io/name: memory-leak-demo
        app.kubernetes.io/part-of: ai-k8s-reliability-security-ops
        app.kubernetes.io/component: demo-workload
    spec:
      serviceAccountName: memory-leak-demo
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: app
          image: ${DEMO_IMAGE}
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
          env:
            - name: CHUNK_MIB
              value: "1"
            - name: INTERVAL_SECONDS
              value: "2"
          # Only a readiness probe: a liveness probe could restart the pod
          # before the kernel OOM kill and muddy the demonstration.
          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 2
            periodSeconds: 5
          resources:
            requests:
              cpu: 20m
              memory: 32Mi
            limits:
              memory: 64Mi
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
