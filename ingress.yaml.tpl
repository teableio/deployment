# Teable Ingress Configuration
# Generated for domain: ${teable_domain}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: teable
  namespace: teable
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "128k"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
    # Uncomment for cert-manager TLS
    # cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  rules:
    - host: ${teable_domain}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: teable
                port:
                  number: 3000
  # Uncomment for TLS
  # tls:
  #   - hosts:
  #       - ${teable_domain}
  #     secretName: teable-tls

