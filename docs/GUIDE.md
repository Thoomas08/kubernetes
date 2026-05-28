# GUIDE COMPLET KUBEQUEST — GROUPE 39

> **Lis ce fichier du début à la fin avant de commencer.**
> Chaque étape est numérotée. Ne passe pas à la suivante avant d'avoir vérifié la précédente.

---

## ÉTAT ACTUEL (ce qui est déjà fait ✅)

| Composant | État |
|---|---|
| Cluster Kubernetes (kube-1 control-plane + kube-2 worker) | ✅ |
| Calico CNI | ✅ |
| ingress-nginx (Helm, namespace `ingress-nginx`) | ✅ |
| kubernetes-dashboard | ✅ |
| kube-prometheus-stack (Prometheus + Grafana + AlertManager) | ✅ |
| Loki + Promtail | ✅ |
| nginx placeholder dans `default` | ⚠️ à remplacer par la vraie app |

## CE QUI RESTE À FAIRE

1. Joindre les VMs `ingress` et `monitoring` au cluster
2. Labelliser les 4 nodes
3. Déplacer les workloads sur les bons nodes (Helm upgrade)
4. Créer les Ingress resources (accès à dashboard, grafana)
5. Installer le storage provider (local-path)
6. Builder et pusher l'image Docker de l'app Laravel
7. Déployer l'app avec Helm OU Kustomize
8. Vérifier le déploiement complet
9. [Bonus] OPA et authentification

---

## PHASE 1 — Joindre les VMs `ingress` et `monitoring` au cluster

### 1.1 — Récupérer le join command (sur kube-1)

SSH sur **kube-1** et exécute :

```bash
sudo kubeadm token create --print-join-command
```

Copie la ligne qui ressemble à :
```
kubeadm join 10.1.39.24:6443 --token xxx.xxx --discovery-token-ca-cert-hash sha256:xxxxx
```

---

### 1.2 — Préparer et joindre la VM `ingress` (sur la VM ingress)

SSH sur la **VM ingress** (node-3 dans AWS), puis :

```bash
# 1. Copier le script d'installation
# (soit tu le colle directement, soit tu le télécharges depuis ton repo)

sudo dnf update -y
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab
sudo modprobe overlay
sudo modprobe br_netfilter

sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-ip6tables=1
EOF

sudo sysctl --system
sudo dnf install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

sudo tee /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
EOF

sudo dnf install -y kubelet kubeadm kubectl
sudo systemctl enable kubelet
sudo systemctl start kubelet

# 2. Coller le join command récupéré depuis kube-1 (avec sudo)
sudo kubeadm join 10.1.39.24:6443 --token XXX --discovery-token-ca-cert-hash sha256:XXX
```

---

### 1.3 — Préparer et joindre la VM `monitoring` (sur la VM monitoring)

SSH sur la **VM monitoring** (node-4 dans AWS) et répéter exactement les mêmes commandes que 1.2.

---

### 1.4 — Vérifier que les 4 nodes sont dans le cluster (sur kube-1)

```bash
kubectl get nodes -o wide
```

Tu dois voir **4 nodes** avec le statut `Ready`.

---

## PHASE 2 — Labelliser les nodes

Sur **kube-1**, récupère les noms des nouveaux nodes :

```bash
kubectl get nodes
```

Puis applique les labels. Remplace `<NOM-NODE-INGRESS>` et `<NOM-NODE-MONITORING>` par les noms réels :

```bash
# Node ingress (node-3)
kubectl label node <NOM-NODE-INGRESS> node-role=ingress
kubectl label node <NOM-NODE-INGRESS> node-role.kubernetes.io/ingress=

# Node monitoring (node-4)
kubectl label node <NOM-NODE-MONITORING> node-role=monitoring
kubectl label node <NOM-NODE-MONITORING> node-role.kubernetes.io/monitoring=

# Vérification
kubectl get nodes --show-labels
```

---

## PHASE 3 — Déplacer les workloads sur les bons nodes

### 3.1 — Déplacer ingress-nginx sur le node ingress

```bash
helm upgrade ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.nodeSelector."node-role"=ingress \
  --set controller.hostNetwork=true \
  --set controller.kind=DaemonSet
```

### 3.2 — Déplacer le monitoring sur le node monitoring

```bash
helm upgrade monitoring monitoring \
  --repo https://prometheus-community.github.io/helm-charts \
  --chart-name kube-prometheus-stack \
  --namespace monitoring \
  --values infrastructure/monitoring/values-prometheus.yaml
```

> **Note :** Si la commande helm upgrade échoue à trouver le repo, remets d'abord le repo :
> ```bash
> helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
> helm repo update
> helm upgrade monitoring prometheus-community/kube-prometheus-stack \
>   --namespace monitoring --values infrastructure/monitoring/values-prometheus.yaml
> ```

### 3.3 — Déplacer Loki sur le node monitoring

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm upgrade loki grafana/loki-stack \
  --namespace logging \
  --values infrastructure/logging/values-loki.yaml
```

### 3.4 — Vérifier que les pods sont sur les bons nodes

```bash
kubectl get pods -A -o wide
```

---

## PHASE 4 — Créer les Ingress resources

> **Avant de commencer :** remplace `VOTRE_IP_INGRESS_NODE` dans les fichiers par l'**IP publique du node ingress** (visible dans la console AWS EC2).

### 4.1 — Récupérer l'IP publique du node ingress

1. Va sur la console AWS EC2
2. Clique sur le node-3 (ingress)
3. Copie l'**IPv4 public address** (ex: `54.123.45.67`)

### 4.2 — Remplacer dans les fichiers YAML

Sur **ton PC** (dans VS Code) ou directement sur kube-1 :

Dans les fichiers suivants, remplace `VOTRE_IP_INGRESS_NODE` par l'IP réelle :
- `infrastructure/ingress/ingress-dashboard.yaml`
- `infrastructure/ingress/ingress-grafana.yaml`
- `applications/my-app/base/ingress.yaml`
- `applications/my-app/base/configmap.yaml`

### 4.3 — Appliquer les Ingress

```bash
kubectl apply -f infrastructure/ingress/ingress-dashboard.yaml
kubectl apply -f infrastructure/ingress/ingress-grafana.yaml
```

### 4.4 — Vérifier l'accès

```bash
kubectl get ingress -A
```

Tu pourras alors accéder à :
- Dashboard : `https://dashboard.<IP>.nip.io`
- Grafana : `http://grafana.<IP>.nip.io` (login: admin / prom-operator)

### 4.5 — Token pour le Dashboard

```bash
kubectl apply -f infrastructure/dashboard/admin-user.yaml
kubectl -n kubernetes-dashboard create token admin-user
```

Copie le token et colle-le dans la page de login du dashboard.

---

## PHASE 5 — Installer le storage provider

> Nécessaire pour que MySQL puisse stocker ses données de façon persistante.

Sur **kube-1** :

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml

# Définir local-path comme StorageClass par défaut
kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Vérifier
kubectl get storageclass
```

---

## PHASE 6 — Builder et pusher l'image Docker de l'app

> Les nodes sont ARM64 (Graviton). Il faut builder sur kube-1 (qui est ARM64).

### 6.1 — Installer Docker sur kube-1

```bash
sudo dnf install docker -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user
newgrp docker
docker --version
```

### 6.2 — Copier le code de l'app sur kube-1

Depuis **ton PC**, copie le dossier sample-app-master sur kube-1 :

```bash
# Sur ton PC (PowerShell ou terminal)
scp -i <ta-cle-ssh.pem> -r "C:\WorkspaceVsCode\T-CLO-902-LYO_2\sample-app-master" ec2-user@<IP-PUBLIQUE-KUBE1>:/home/ec2-user/
```

### 6.3 — Builder l'image

Sur **kube-1** :

```bash
cd /home/ec2-user/sample-app-master

# Remplace ton_username par ton vrai username Docker Hub
docker build -t ton_username/my-laravel-app:latest .

# Vérifier que l'image est bien créée
docker images
```

### 6.4 — Pusher sur Docker Hub

```bash
docker login
# Entre ton username et mot de passe Docker Hub

docker push ton_username/my-laravel-app:latest
```

---

## PHASE 7 — Déployer l'application

> Choisis **MÉTHODE A (Helm)** OU **MÉTHODE B (Kustomize)**.
> Pour la démo, Helm est recommandé. Kustomize montre le GitOps.

### Avant de déployer : remplacer le placeholder

Dans `applications/my-app/helm-chart/values.yaml`, remplace :
- `VOTRE_USERNAME_DOCKERHUB` → ton username Docker Hub
- `VOTRE_IP_INGRESS_NODE` → l'IP publique du node ingress

---

### MÉTHODE A — Déploiement avec Helm

Sur **kube-1**, depuis le dossier du repo :

```bash
# Créer le namespace
kubectl create namespace my-app

# Déployer
helm install my-app ./applications/my-app/helm-chart \
  --namespace my-app \
  --set image.repository=ton_username/my-laravel-app \
  --set ingress.host=my-app.<IP-INGRESS>.nip.io \
  --set app.url=http://my-app.<IP-INGRESS>.nip.io

# Suivre le déploiement
kubectl get pods -n my-app -w
```

---

### MÉTHODE B — Déploiement avec Kustomize

```bash
# Créer le namespace
kubectl create namespace my-app

# Déployer l'overlay de production
kubectl apply -k applications/my-app/overlays/prod

# Suivre le déploiement
kubectl get pods -n my-app -w
```

---

### 7.1 — Vérifier que l'app fonctionne

```bash
# Voir tous les pods
kubectl get pods -n my-app

# Voir les logs de l'app
kubectl logs -l app.kubernetes.io/name=my-app -n my-app --container app

# Tester l'API
curl http://my-app.<IP-INGRESS>.nip.io/api/counter
```

La réponse attendue :
```json
{"value": 0}
```

```bash
# Incrémenter le compteur
curl -X POST http://my-app.<IP-INGRESS>.nip.io/api/counter/add
```

---

### 7.2 — Mettre à jour l'app (Rolling Update)

```bash
# Rebuild + push une nouvelle version
docker build -t ton_username/my-laravel-app:v2 .
docker push ton_username/my-laravel-app:v2

# Avec Helm
helm upgrade my-app ./applications/my-app/helm-chart \
  --namespace my-app \
  --set image.tag=v2

# Voir le rollout
kubectl rollout status deployment/my-app -n my-app

# Rollback si problème
kubectl rollout undo deployment/my-app -n my-app
```

---

## PHASE 8 — Vérifications finales

```bash
# 1. Tous les pods tournent
kubectl get pods -A

# 2. Les ingress sont créés
kubectl get ingress -A

# 3. Les PVC sont bound
kubectl get pvc -A

# 4. Le backup CronJob est présent
kubectl get cronjob -A

# 5. Déclencher un backup manuel pour tester
kubectl create job --from=cronjob/my-app-mysql-backup test-backup -n my-app
kubectl logs job/test-backup -n my-app

# 6. Voir les métriques dans Grafana
# → http://grafana.<IP>.nip.io

# 7. Voir les logs dans Grafana (Explore → Loki)
# → http://grafana.<IP>.nip.io → Explore → source: Loki
```

---

## PHASE 9 — Checklist avant la démo

Vérifie chaque point :

- [ ] `kubectl get nodes` → 4 nodes `Ready`
- [ ] `kubectl get pods -A` → tous les pods `Running`
- [ ] `kubectl get ingress -A` → ingress pour app, dashboard, grafana
- [ ] Dashboard accessible via le navigateur
- [ ] Grafana accessible via le navigateur (métriques visibles)
- [ ] Loki configuré dans Grafana (logs visibles)
- [ ] App Laravel accessible : `curl http://my-app.<IP>.nip.io`
- [ ] API Counter fonctionne : `curl -X POST http://my-app.<IP>.nip.io/api/counter/add`
- [ ] PVC MySQL `Bound` : `kubectl get pvc -n my-app`
- [ ] Backup CronJob présent : `kubectl get cronjob -n my-app`
- [ ] Secrets utilisés (pas de mots de passe en clair) : `kubectl get secrets -n my-app`

---

## ANNEXE A — Récapitulatif des commandes utiles

```bash
# Voir tous les pods de tous les namespaces
kubectl get pods -A -o wide

# Voir les logs d'un pod
kubectl logs <nom-du-pod> -n <namespace>

# Entrer dans un pod
kubectl exec -it <nom-du-pod> -n <namespace> -- /bin/bash

# Décrire un pod (voir les events en cas d'erreur)
kubectl describe pod <nom-du-pod> -n <namespace>

# Voir les Helm releases
helm list -A

# Voir l'historique d'un déploiement
kubectl rollout history deployment/my-app -n my-app

# Rollback
kubectl rollout undo deployment/my-app -n my-app

# Forcer un redémarrage des pods
kubectl rollout restart deployment/my-app -n my-app
```

---

## ANNEXE B — Structure du repo

```
applications/my-app/
  helm-chart/              ← Helm chart complet (app + MySQL)
    Chart.yaml
    values.yaml            ← MODIFIER : username dockerhub et IP ingress
    templates/
      app-deployment.yaml  ← Déploiement de l'app Laravel
      mysql-deployment.yaml← Déploiement MySQL
      secret.yaml          ← Secrets (APP_KEY, mots de passe)
      configmap.yaml       ← Variables de config
      ingress.yaml         ← Ingress vers l'app
      backup-cronjob.yaml  ← Backup MySQL quotidien

  base/                    ← Base Kustomize
    kustomization.yaml
    deployment.yaml        ← MODIFIER : VOTRE_USERNAME_DOCKERHUB
    configmap.yaml         ← MODIFIER : IP ingress
    ingress.yaml           ← MODIFIER : IP ingress
    ...

  overlays/
    dev/                   ← Env dev (1 replica, debug=true)
    prod/                  ← Env prod (3 replicas)

infrastructure/
  ingress/
    ingress-dashboard.yaml ← MODIFIER : IP ingress
    ingress-grafana.yaml   ← MODIFIER : IP ingress
  monitoring/
    values-prometheus.yaml ← Values Helm pour Prometheus
  logging/
    values-loki.yaml       ← Values Helm pour Loki
  dashboard/
    admin-user.yaml        ← ServiceAccount dashboard
```

---

## ANNEXE C — Routes de l'API Laravel

| Route | Méthode | Description |
|---|---|---|
| `/` | GET | Page d'accueil |
| `/api/counter` | GET | Lire la valeur du compteur |
| `/api/counter/add` | POST | Incrémenter le compteur |

---

## ANNEXE D — Ordre de déploiement pour la démo finale

Pour la démo, le jury veut voir un déploiement depuis zéro avec `kubectl apply` / `helm install` :

```bash
# 1. Infra réseau
helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace

# 2. Monitoring
helm install monitoring prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace --values infrastructure/monitoring/values-prometheus.yaml

# 3. Logging
helm install loki grafana/loki-stack --namespace logging --create-namespace --values infrastructure/logging/values-loki.yaml

# 4. Dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
kubectl apply -f infrastructure/dashboard/admin-user.yaml

# 5. Ingress vers les services
kubectl apply -f infrastructure/ingress/ingress-dashboard.yaml
kubectl apply -f infrastructure/ingress/ingress-grafana.yaml

# 6. Application
helm install my-app ./applications/my-app/helm-chart --namespace my-app --create-namespace
```
