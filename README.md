# Kata Fullstack 2026 – Infraestructura

Este repositorio contiene lo necesario para levantar y desplegar toda la aplicación: la orquestación con Docker Compose y los scripts para desplegarla en AWS EC2.

## Repositorios del proyecto

| Parte | Repositorio |
|-------|-------------|
| Backend | https://github.com/paolaPerez00/kata-back-fullstack-2026 |
| Frontend | https://github.com/paolaPerez00/kata-front-fullstack-2026 |
| Infraestructura (este repo) | https://github.com/paolaPerez00/kata-infra-fullstack-2026 |

## Contenido

```
.
├── docker-compose.yml   # Orquesta db, backend, web y seed
├── .env.example         # Variables de entorno de ejemplo
└── aws/
    ├── create-ec2.sh    # Crea la instancia EC2 y despliega la app
    └── destroy-ec2.sh   # Elimina la instancia y el security group
```

## Servicios (docker-compose)

| Servicio | Descripción |
|----------|-------------|
| `db` | PostgreSQL 16 con volumen persistente y healthcheck |
| `backend` | API construida desde el repo del backend. Monta el socket de Docker para ejecutar el código de los usuarios en contenedores |
| `web` | Frontend construido desde el repo del frontend, expuesto en el puerto 80 (configurable con `WEB_PORT`) |
| `seed` | Carga datos iniciales. Solo corre bajo el perfil `seed` |

## Ejecución local

Requisitos: Docker y Docker Compose.

1. Clona los tres repositorios en la misma carpeta:

   ```bash
   git clone https://github.com/paolaPerez00/kata-infra-fullstack-2026.git
   cd kata-infra-fullstack-2026
   git clone https://github.com/paolaPerez00/kata-back-fullstack-2026.git
   git clone https://github.com/paolaPerez00/kata-front-fullstack-2026.git
   ```

2. Crea el archivo de entorno:

   ```bash
   cp .env.example .env
   ```

3. Prepara el directorio de ejecución y levanta los servicios:

   ```bash
   mkdir -p /tmp/kata-exec
   docker compose up -d --build
   ```

4. Carga los datos iniciales:

   ```bash
   docker compose --profile seed run --rm seed
   ```

5. Abre http://localhost (o el puerto definido en `WEB_PORT`).

### Variables de entorno

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| `DB_USER` | Usuario de PostgreSQL | `kata` |
| `DB_PASSWORD` | Contraseña de PostgreSQL (define una propia) | `<tu-contraseña>` |
| `DB_NAME` | Nombre de la base de datos | `kata_db` |
| `WEB_PORT` | Puerto del frontend (opcional, por defecto 80) | `80` |

> El archivo `.env` no se versiona. Usa `.env.example` como plantilla.

## Despliegue en AWS

Requisitos: AWS CLI configurado con credenciales que puedan crear recursos EC2, IAM y SSM.

Desde la carpeta donde está `docker-compose.yml`:

```bash
REPO_BACK=https://github.com/paolaPerez00/kata-back-fullstack-2026.git \
REPO_FRONT=https://github.com/paolaPerez00/kata-front-fullstack-2026.git \
./aws/create-ec2.sh
```

El script:

1. Crea un rol IAM con acceso por Session Manager (sin SSH ni claves).
2. Crea un security group que solo abre el puerto 80.
3. Lanza una instancia `t3.small` con Ubuntu 24.04 y 20 GB de disco.
4. Al arrancar, la instancia instala Docker, clona el back y el front, genera una contraseña aleatoria para la base de datos, levanta los servicios y ejecuta el seed.
5. Imprime la URL pública. Queda disponible a los 5-10 minutos, cuando termina el build.

La región por defecto es `us-east-1` y se cambia con la variable `REGION`.

### Eliminar los recursos

```bash
./aws/destroy-ec2.sh
```

Termina la instancia y borra el security group.
