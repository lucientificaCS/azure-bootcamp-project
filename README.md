# Proyecto Final - Bootcamp Azure (LEAD UTP)

## Descripción

Este proyecto consiste en una aplicación web sencilla desarrollada con Python y Flask, ejecutada dentro de un contenedor Docker y desplegada en Azure Container Apps.

El objetivo principal es poner en práctica varios de los servicios y conceptos trabajados durante el bootcamp.

---

## Arquitectura General

```text
GitHub
   │
   ├── CI (Pruebas, validaciones y construcción)
   ▼
Azure Container Registry (ACR)
   │
   ▼
Azure Container Apps
   │
   ├── Consulta secretos usando Managed Identity
   ▼
Azure Key Vault

Logs y métricas
   ▼
Log Analytics Workspace
```

---

## Relación con los Temas del Bootcamp

### Fundamentos de Azure y Azure CLI

Todos los recursos se crean mediante Azure CLI utilizando un grupo de recursos dedicado:

```text
rg-retailandes-dev
```

La infraestructura se despliega completamente desde consola.

### Observabilidad

Se integra un Log Analytics Workspace para el monitoreo de la aplicación.

También se implementa un endpoint de verificación:

```text
/health
```

para validar el estado del servicio.

### Contenedores

La aplicación cuenta con un Dockerfile propio.

La imagen se compila y almacena en Azure Container Registry para posteriormente desplegarse en Azure Container Apps.

### Seguridad

La solución utiliza Managed Identity para acceder a recursos internos sin exponer credenciales.

La aplicación obtiene un secreto almacenado en Azure Key Vault mediante permisos RBAC mínimos.

### Infraestructura como Código

Toda la infraestructura se define en:

```text
infra/main.bicep
```

permitiendo recrear el entorno de forma consistente.

### Integración Continua (CI)

Se incluye un flujo de GitHub Actions que ejecuta:

- Pruebas unitarias.
- Validación de la plantilla Bicep.
- Verificaciones básicas de funcionamiento.

---

## Estructura del Repositorio

```text
.
├── app/
│   ├── Código fuente Flask
│   ├── Dockerfile
│   └── Tests
│
├── infra/
│   └── main.bicep
│
└── .github/
    └── workflows/
        └── ci.yml
```

---

## Guía de Despliegue

### 1. Iniciar sesión y registrar proveedores

```bash
az login

az provider register -n Microsoft.App
az provider register -n Microsoft.OperationalInsights
az provider register -n Microsoft.ContainerRegistry
az provider register -n Microsoft.KeyVault
```

### 2. Crear el grupo de recursos

```bash
az group create \
  -n rg-retailandes-dev \
  -l eastus2 \
  --tags project=bootcamp-azure env=dev
```

### 3. Desplegar la infraestructura base

```bash
az deployment group create \
  -g rg-retailandes-dev \
  -f infra/main.bicep \
  -p demoSecretValue='valor-secreto-de-prueba' \
  -n main
```

### 4. Construir la imagen en Azure Container Registry

```bash
ACR=$(az deployment group show \
  -g rg-retailandes-dev \
  -n main \
  --query properties.outputs.acrName.value \
  -o tsv)

az acr build \
  -r $ACR \
  -t retail-app:v1 \
  ./app
```

### 5. Actualizar la aplicación con la nueva imagen

```bash
az deployment group create \
  -g rg-retailandes-dev \
  -f infra/main.bicep \
  -n main \
  -p demoSecretValue='valor-secreto-de-prueba' \
  image=$ACR.azurecr.io/retail-app:v1
```

### 6. Verificar el despliegue

```bash
URL=$(az deployment group show \
  -g rg-retailandes-dev \
  -n main \
  --query properties.outputs.appUrl.value \
  -o tsv)

curl $URL/health
curl $URL/secret-check
```

