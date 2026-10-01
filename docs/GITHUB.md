# GitHub RELOJ-CONTROL

Destino indicado por el usuario: https://github.com/cloud-Csuazo/RELOJ-CONTROL.git. El repositorio estaba vacío al comprobarlo. La entrega se publicó exitosamente en main. Git local usa esa rama; no se versionan `.env.local`, dependencias, builds ni artefactos temporales. Las capturas y documentación sí forman parte de la entrega.

Para publicar cambios futuros desde una terminal con Git instalado y autenticación GitHub disponible:

```sh
git push -u origin main
```

Si Git solicita autenticar, utilizar el flujo de GitHub o GitHub Desktop en tu equipo. No pegar tokens por chat ni incorporarlos a la URL remota. En Desktop, File → Add local repository, seleccionar la carpeta `outputs/fase-1` de esta entrega y publicar/sincronizar hacia el remoto configurado. Revisar en GitHub que la visibilidad elegida sea privada para este proyecto interno.

El primer commit documenta la implementación entregada; su autor técnico es Codex, sin modificar tu identidad global de Git. Configura tu nombre y correo para commits futuros mediante la interfaz de GitHub Desktop o configuración local de Git.

No existe despliegue automático ni ejecución de migraciones al hacer push. Configurar Supabase localmente con la guía correspondiente. Nunca subir archivos `.env.local`, claves secretas, datos reales de trabajadores ni documentos privados.

Fuente: [añadir un repositorio local a GitHub Desktop](https://docs.github.com/en/desktop/adding-and-cloning-repositories/adding-a-repository-from-your-local-computer-to-github-desktop).
