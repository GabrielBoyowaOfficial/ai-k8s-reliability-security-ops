apiVersion: apps/v1
kind: Deployment
metadata:
  name: devops-agent-operator
  namespace: devops-agent-operator-system
  labels:
    app.kubernetes.io/name: devops-agent-operator
    app.kubernetes.io/part-of: ai-k8s-reliability-security-ops
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: devops-agent-operator
  template:
    metadata:
      labels:
        app.kubernetes.io/name: devops-agent-operator
        app.kubernetes.io/part-of: ai-k8s-reliability-security-ops
    spec:
      # Bound to the Pod Identity role by aws_eks_pod_identity_association.
      serviceAccountName: devops-agent-operator
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: manager
          image: ${OPERATOR_IMAGE}
          imagePullPolicy: IfNotPresent
          command: ["/manager"]
          args:
            - --leader-elect
            - --health-probe-bind-address=:8081
          ports:
            - name: health
              containerPort: 8081
          envFrom:
            - configMapRef:
                name: devops-agent-operator-config
          env:
            # Both values come from the Secret created by scripts/configure-webhook.sh.
            - name: DEVOPS_AGENT_WEBHOOK_URL
              valueFrom:
                secretKeyRef:
                  name: devops-agent-operator-webhook
                  key: webhook-url
            - name: DEVOPS_AGENT_WEBHOOK_SECRET
              valueFrom:
                secretKeyRef:
                  name: devops-agent-operator-webhook
                  key: webhook-secret
            - name: EKS_CLUSTER_NAME
              value: "${EKS_CLUSTER_NAME}"
            - name: AWS_ACCOUNT_ID
              value: "${AWS_ACCOUNT_ID}"
            - name: CLOUDWATCH_LOG_GROUP
              value: "${INCIDENT_LOG_GROUP}"
            - name: S3_BUCKET
              value: "${INCIDENT_BUCKET}"
            - name: S3_PREFIX
              value: "incidents"
          securityContext:
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8081
            initialDelaySeconds: 15
            periodSeconds: 20
          readinessProbe:
            httpGet:
              path: /readyz
              port: 8081
            initialDelaySeconds: 5
            periodSeconds: 10
          resources:
            requests:
              cpu: 10m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 128Mi
      terminationGracePeriodSeconds: 10
