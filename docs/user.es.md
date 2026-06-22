# Navius GPS — Manual de usuario

[Web](https://www.egpsistemas.com/site/navius) · [GitHub](https://github.com/woodyst/navius) · [Donaciones](https://liberapay.com/Navius-GPS/)

## Tabla de contenidos

1. [Primeros pasos](#primeros-pasos)
2. [Cuenta Navius](#cuenta-navius)
3. [El mapa](#el-mapa)
4. [Buscar un destino](#buscar-un-destino)
5. [Planificar una ruta](#planificar-una-ruta)
6. [TODOs por destino](#todos-por-destino)
7. [Hora de salida y planes guardados](#hora-de-salida-y-planes-guardados)
8. [Selección de ruta](#selección-de-ruta)
9. [Navegación turn-by-turn](#navegación-turn-by-turn)
10. [Compartir viaje](#compartir-viaje)
11. [Reproductor de música](#reproductor-de-música)
12. [Voz (TTS)](#voz-tts)
13. [Velocímetro y límites de velocidad](#velocímetro-y-límites-de-velocidad)
14. [Alertas comunitarias](#alertas-comunitarias)
15. [Mensajes del servidor](#mensajes-del-servidor)
16. [Vista de satélites GPS](#vista-de-satélites-gps)
17. [Grabación de tracks](#grabación-de-tracks)
18. [Servidor Valhalla y tráfico](#servidor-valhalla-y-tráfico)
19. [Ajustes](#ajustes)
20. [Datos y privacidad](#datos-y-privacidad)

---

## Primeros pasos

Al abrir Navius por primera vez, el asistente de bienvenida recorre todas las funciones de la app. Puedes volver a él en cualquier momento desde **Ajustes → Ayuda → Abrir asistente**.

Para que Navius funcione correctamente necesitas:

- **Conexión a internet** para la búsqueda de lugares y el cálculo de rutas (o un servidor Valhalla local)
- **Permiso de ubicación** para recibir la posición GPS del dispositivo

La primera vez que el GPS obtiene señal puede tardar hasta 1-2 minutos (cold fix). Una vez fijado, los siguientes fixes son instantáneos.

---

## Cuenta Navius

### Registro e inicio de sesión

Navius dispone de un servidor comunitario que te permite sincronizar tus ajustes entre dispositivos, reportar alertas de tráfico y compartir tu posición en tiempo real.

Para crear una cuenta:

1. Abre el menú **≡** (esquina superior derecha)
2. Toca **Cuenta / Login**
3. Selecciona **Registrarse** e introduce tu email y contraseña
4. Recibirás un email de verificación; toca el enlace para activar la cuenta

Si ya tienes cuenta, selecciona **Iniciar sesión** e introduce tus credenciales.

### Sincronización de ajustes

Una vez con sesión activa, Navius sincroniza automáticamente tus ajustes con el servidor:

- **Al cambiar un ajuste**: el cambio se sube al servidor automáticamente unos 3 segundos después
- **Al abrir la app**: si hay ajustes más recientes en el servidor (por ejemplo, los cambiaste desde otro dispositivo), Navius lo detecta y te pregunta qué hacer

### Conflicto de ajustes

Si tienes cambios locales sin sincronizar y también hay cambios nuevos en el servidor, aparecerá un diálogo con dos opciones:

- **Usar servidor**: aplica los ajustes del servidor y descarta los cambios locales
- **Mantener local**: conserva tus ajustes actuales y los sube al servidor

Los ajustes sincronizados incluyen: estilo de mapa, opciones de ruta, configuración GPS, alertas de velocidad, motor TTS, idioma, tipo de vehículo y más (41 ajustes en total). No se sincronizan la posición GPS, el estado de la navegación activa ni las opciones de depuración.

---

## El mapa

### Navegar por el mapa

- **Mover**: desliza un dedo en cualquier dirección
- **Zoom**: pellizca con dos dedos o usa la barra de zoom lateral
- **Rotar**: gira con dos dedos (en modo Norte arriba el mapa vuelve a norte automáticamente)
- **Recentrar**: toca el botón de brújula para volver a tu posición y activar el seguimiento

### Modos de vista

| Botón | Efecto |
|-------|--------|
| **2D / 3D** | Alterna entre vista plana y perspectiva de conducción inclinada. En 3D se ven los edificios extruidos |
| **Norte / Rumbo** | El mapa puede apuntar siempre al norte o girar según tu dirección de movimiento |
| **Brújula** | Recentra en tu posición y activa el seguimiento continuo |

### Modos de mapa

El botón de estilo del mapa (en la esquina del mapa) permite ciclar entre los estilos disponibles. Toca para pasar al siguiente; el nombre del estilo actual se muestra bajo el icono.

| Estilo | Icono | Descripción |
|--------|-------|-------------|
| **Auto** | ⊙ | Cambia automáticamente según la posición del sol (día de ~7h a ~20h, noche el resto) |
| **Satélite** | 🛰 | Imágenes de satélite de alta resolución |
| **Positron** | ☀ | Mapa claro minimalista |
| **Vivo** | 🌐 | Mapa claro con colores vivos |
| **Fiord** | 🌊 | Mapa oscuro suave (noche automática en modo Auto) |
| **Noche** | 🌙 | Mapa oscuro intenso |

En modo **Auto**: el mapa usa el estilo claro durante el día y cambia al estilo Fiord por la noche (según la posición del sol, no la hora fija). Si tienes el servidor Navius configurado, están disponibles los estilos Fiord y Noche; en caso contrario se usan estilos equivalentes de proveedores externos.

> **Nota**: el modo **Noche** explícito usa el estilo oscuro intenso; el modo **Auto** de noche usa Fiord (más suave). El botón de ciclo de estilo solo muestra los estilos disponibles según el servidor configurado.

### Modo horizontal (landscape)

Al girar el dispositivo en horizontal, el mapa ocupa todo el alto de la pantalla y el panel de navegación (barra superior con instrucción, velocidad, etc.) se desplaza al lado izquierdo, dejando más espacio al mapa.

---

## Buscar un destino

1. Toca el botón **«Iniciar navegación»** en la parte superior para abrir el panel de planificación
2. Escribe el nombre de un lugar, dirección, ciudad o coordenadas (ej. `40.4168, -3.7038`)
3. Los resultados provienen de OpenStreetMap mediante el geocodificador Photon/Komoot
4. Toca un resultado para añadirlo como destino

### Búsqueda de POI

En el panel de planificación, la sección **POI cercanos** te permite buscar puntos de interés cerca de tu posición actual o de cualquier destino añadido:

- Gasolineras — muestran el **precio del combustible** cuando está disponible en OSM
- Aparcamientos
- Restaurantes y cafeterías
- Hoteles
- Supermercados
- Hospitales y farmacias
- Y más categorías

Toca un POI para ver su información (horario, teléfono, web, precio…) y añadirlo como destino.

### Historial y favoritos

- El **historial** guarda los últimos 50 destinos buscados automáticamente
- Los **favoritos** son lugares guardados manualmente con un nombre personalizado
- Ambos aparecen en el panel de planificación sin necesidad de buscar

Para añadir un favorito: busca el lugar → toca el icono de estrella junto al resultado.

---

## Planificar una ruta

### Ruta con múltiples paradas

Navius permite añadir tantos destinos como necesites. La ruta pasa por todos en orden:

1. Añade el primer destino
2. Toca **+ Añadir parada** para agregar más destinos
3. Usa las flechas ↑↓ para reordenar las paradas
4. Toca la **×** para eliminar una parada

### Opciones de ruta

Antes de calcular puedes activar o desactivar:

| Opción | Efecto |
|--------|--------|
| **Sin peajes** | Evita carreteras de peaje |
| **Sin autopistas** | Evita autovías y autopistas |
| **Sin ferries** | Evita travesías en ferry |
| **Sin tierra** | Evita pistas de tierra o grava |

---

## TODOs por destino

Puedes asociar una lista de tareas a cualquier destino del viaje.

### Añadir tareas

1. En el panel de planificación, expande un destino
2. Toca **+ Tarea**
3. Escribe el texto de la tarea y confirma

Las tareas quedan asociadas a las coordenadas del destino y se guardan automáticamente.

### Gestionar tareas durante la navegación

Al llegar al destino, Navius muestra un aviso en pantalla. Toca **Abrir** para ver la lista de tareas pendientes y marcarlas como completadas una a una.

### Persistencia

Los TODOs se guardan indefinidamente. La próxima vez que planifiques una ruta a ese mismo lugar (mismas coordenadas), verás las tareas guardadas de sesiones anteriores.

---

## Hora de salida y planes guardados

### Programar la hora de salida

Activa el toggle **Hora de salida** en la parte inferior del panel de planificación. Aparecerán dos selectores:

- **Día**: Hoy, Mañana, Pasado mañana, etc.
- **Hora y minutos**: rueda de selección HH:MM (intervalos de 5 minutos)

La ruta se calculará usando el perfil de tráfico correspondiente a ese momento del día. Por ejemplo, una ruta del lunes a las 8:00 usará los tiempos de tráfico punta matutino.

### Guardar un plan de viaje

Pulsa el botón **⊕** junto al botón CALCULAR RUTA para guardar el plan actual. Un plan incluye:

- Todos los destinos y sus TODOs
- Hora de salida programada (si está activa)
- Opciones de ruta (sin peajes, etc.)
- Nombre generado automáticamente con el destino final y la hora

### Cargar y borrar planes

Los planes guardados aparecen en la sección **Planes guardados** en la parte superior del panel de planificación:

- Toca un plan para cargarlo (restaura todos los destinos, TODOs y configuración)
- Si la fecha de salida ya pasó, se ajusta automáticamente al próximo día a la misma hora
- Toca el icono **🗑** para borrar el plan

---

## Selección de ruta

Tras pulsar **CALCULAR RUTA**, aparece el panel de selección con hasta 3 alternativas:

- Cada alternativa muestra: distancia total, tiempo estimado y perfil de velocidad
- La ruta se dibuja en el mapa al seleccionarla
- Puedes cambiar el **tipo de vehículo** (coche, moto, bicicleta, a pie, camión…)
- Toca **Ver instrucciones** para ver la lista completa de maniobras antes de salir
- Toca **Iniciar** para comenzar la navegación

---

## Navegación turn-by-turn

### Barra de navegación

Durante la navegación, la barra superior muestra:

| Elemento | Descripción |
|----------|-------------|
| **Icono de maniobra** | Flecha o símbolo de la próxima maniobra |
| **Distancia al giro** | Metros u km al próximo giro |
| **Nombre de calle** | Calle actual y nombre de la siguiente |
| **Velocidad** | Tu velocidad actual en km/h |
| **Límite** | Límite de velocidad del tramo actual |
| **Resumen del tramo** | Distancia · tiempo · ETA al próximo waypoint |
| **Resumen total** | Distancia · tiempo · ETA al destino final |

La **ETA** (hora estimada de llegada) se calcula sumando el tiempo restante a la hora actual y se muestra en formato HH:MM.

### Instrucciones de voz

Las instrucciones se anuncian por voz con la suficiente antelación para reaccionar. El motor TTS activo (Piper, Mimic o PicoTTS) genera el audio en tiempo real.

### Recálculo de ruta

Si te desvías de la ruta, Navius recalcula automáticamente la ruta desde tu posición actual hasta el próximo destino.

### Llegada a destinos intermedios

Al llegar a cada parada intermedia, Navius avisa y, si hay TODOs pendientes, muestra el banner para abrirlos. La navegación continúa automáticamente hacia la siguiente parada al confirmar.

### Detener la navegación

Toca el botón **Stop** (■) en la barra de navegación o desliza para cerrar el panel.

### Recuperación de ruta al arrancar

Si cierras Navius con una navegación activa, al volver a abrirlo aparece un diálogo que te pregunta si deseas continuar con la ruta anterior. Toca **Continuar** para reanudar desde tu posición actual, o **Descartar** para empezar de nuevo.

### Rutas alternativas por tráfico

Durante la navegación, Navius comprueba periódicamente si existe una ruta alternativa significativamente más rápida. Si la detecta, aparece un banner en la parte inferior con el tiempo ahorrado. Toca **Ver alternativa** para compararla en el mapa y decidir si quieres cambiar.

---

## Compartir viaje

La función de compartir viaje te permite que otras personas vean tu posición y ruta en tiempo real desde cualquier navegador web, sin necesidad de que tengan Navius instalado.

**Requisito**: necesitas tener una cuenta Navius activa (sesión iniciada).

### Activar el share

1. Abre el menú **≡**
2. Toca **Compartir viaje**
3. Toca **Crear enlace** — Navius genera un enlace único en `https://navius-api.egpsistemas.com/share/…`
4. Toca **Copiar** para copiar el enlace al portapapeles, o compártelo directamente por WhatsApp, Telegram u otra aplicación

Mientras el share está activo, el ítem del menú se muestra en rojo con el texto **Compartiendo**.

### Lo que ve el seguidor

La página del seguidor muestra en tiempo real:

- El **mapa** con tu posición actual y el icono de vehículo apuntando en tu dirección
- Tu **ruta activa** dibujada en el mapa (solo el tramo restante, se va recortando según avanzas)
- Tu **velocidad** actual en km/h
- **Destinos** con distancia restante y hora estimada de llegada (ETA)

La página del seguidor incluye:

- **Selector de estilo de mapa**: puede elegir entre Auto, Noche (Fiord), Día (Liberty), Positron y Bright
- **Botón Centrar** (◎): aparece cuando el seguidor mueve el mapa manualmente; toca para volver a seguir tu posición automáticamente
- **Auto-seguimiento**: la página sigue tu posición automáticamente con animación suave; si el seguidor mueve el mapa, el auto-seguimiento se pausa hasta que toca Centrar

La posición se actualiza cada 5 segundos mientras Navius esté en primer plano con navegación activa.

### Cuando Navius se cierra

Si cierras Navius o la app pasa a segundo plano y deja de enviar actualizaciones, la página del seguidor muestra un banner **"Navius cerrado · Última posición conocida"** con la última posición recibida. El enlace sigue siendo válido durante 24 horas.

### Renovación automática de sesión

Si al intentar crear o actualizar el share tu sesión ha expirado (token caducado), Navius renueva el token automáticamente sin necesidad de que vuelvas a hacer login. Esta renovación funciona hasta 90 días después de que expire el token original.

### Detener el share

1. Abre el menú **≡**
2. Toca **Compartiendo** (aparece en rojo cuando hay un share activo)
3. Toca **Detener**

El permiso se revoca inmediatamente: la página del seguidor dejará de recibir actualizaciones en cuanto recargue.

---

## Reproductor de música

Navius incluye un reproductor de música integrado accesible desde el menú **≡ → Música**.

### Abrir el reproductor

1. Abre el menú **≡**
2. Toca **Música**
3. Navega por las carpetas de `~/Music` para localizar tu música
4. Toca una pista para reproducirla

### Formatos soportados

mp3, ogg, flac, m4a, opus, wav, aac, oga, wma

### Controles

- **▶ / ⏸**: reproducir / pausar
- **⏮ / ⏭**: pista anterior / siguiente
- **Barra de volumen**: ajusta el volumen de reproducción
- **×**: cerrar el reproductor y detener la música

### Widget de música

Mientras hay una pista en reproducción, aparece una pequeña barra compacta encima de la barra de estado con el nombre de la pista y los controles básicos. Es visible aunque el panel de música esté cerrado.

### Ducking con TTS

Cuando Navius pronuncia una instrucción de navegación por voz, el volumen de la música baja automáticamente al 15 %. Se restaura 600 ms después de que termine la instrucción.

---

## Voz (TTS)

Navius incluye tres motores de síntesis de voz seleccionables en **Ajustes → Voz**:

### Piper (recomendado)

- Calidad neural, la voz más natural
- Latencia ~300 ms (Navius pre-genera los audios en segundo plano)
- Soporta múltiples idiomas con voces `.onnx`
- Descarga voces adicionales desde **Ajustes → Voz → Ver voces disponibles**

### Mimic HTS

- Síntesis HTS, buena calidad en español
- Latencia ~100 ms
- Voz española integrada, sin descargas necesarias

### PicoTTS

- Motor concatenativo básico
- Latencia ~50 ms (muy rápido)
- Idiomas: español, inglés, alemán, francés, italiano

### Configuración de voz

En **Ajustes → Voz** puedes:

- Seleccionar el motor
- Elegir idioma (español, inglés, francés, alemán, etc.)
- Seleccionar una voz concreta dentro del motor
- Probar la voz con texto libre

---

## Velocímetro y límites de velocidad

### Velocímetro

El cuentakilómetros circular muestra tu velocidad actual en tiempo real.

### Límites de velocidad

Navius puede obtener el límite de velocidad de varias fuentes. Cuando superas el límite, el indicador en la barra de navegación cambia de color.

**Prioridad del límite para la alerta de color:**

1. **Radar OSM** — si la ruta pasa por un radar fijo o de tramo con velocidad máxima definida en OpenStreetMap
2. **Límite comunitario** — si otro usuario de Navius ha reportado un límite en ese tramo
3. **Límite de la vía** — límite de velocidad de la carretera según OSM (solo si la opción **Mostrar velocidad máxima de la vía** está activada en Ajustes; desactivada por defecto porque la cobertura de esta información en OSM no es fiable)

Si ninguna de estas fuentes está disponible, el indicador no muestra alerta de color aunque vayas a alta velocidad.

### Configurar las alertas

En **Ajustes → General**:

- **Alerta de velocidad**: activa/desactiva la alerta visual y sonora
- **Umbral**: porcentaje sobre el límite que dispara la alerta (por defecto: 1%, equivalente a 1 km/h de margen)
- **Mostrar velocidad máxima de la vía**: activa el uso del límite OSM de la vía como fuente de alertas (fuente no siempre fiable; desactivado por defecto)

---

## Alertas comunitarias

Las alertas comunitarias son avisos que otros conductores de Navius reportan en tiempo real y que aparecen en tu mapa durante la navegación.

**Requisito**: necesitas tener una cuenta Navius activa (sesión iniciada).

### Tipos de alerta

| Categoría | Subtipos disponibles |
|-----------|----------------------|
| Tráfico | Normal · Denso · Detenido |
| Policía / Radar | Cámara móvil · Radar oculto |
| Accidente | Simple · Colisión múltiple |
| Peligro | Obras · Coche en arcén · Semáforo estropeado · Bache |
| Carretera cortada | — |
| Carril bloqueado | Izquierdo · Derecho · Central |
| Error de mapa | (con descripción de texto) |
| Mal tiempo | Calzada resbaladiza · Inundación · Nieve · Niebla · Hielo |

### Cómo se muestran

Durante la navegación, solo verás las alertas que estén en tu ruta activa (filtradas por proximidad). Si hay una alerta próxima, Navius emite un aviso sonoro y muestra el icono de la alerta en el mapa.

### Cómo reportar una alerta

1. Toca el botón de alerta en el mapa (icono triangular de advertencia)
2. Selecciona la categoría y, si aplica, el subtipo
3. Confirma — la alerta se envía al servidor con tu posición y rumbo actuales

Las alertas tienen una vigencia limitada. Otros usuarios pueden confirmarlas o desmentirlas con los botones de voto que aparecen al tocar el marcador.

---

## Mensajes del servidor

El servidor comunitario de Navius puede enviarte mensajes informativos: avisos de mantenimiento, novedades de la app o notificaciones dirigidas a tu dispositivo.

**Requisito**: necesitas tener una cuenta Navius activa (sesión iniciada).

### Ver mensajes

1. Abre el menú **≡**
2. Toca **Mensajes** — si hay mensajes sin leer aparece un contador junto al icono
3. Toca un mensaje para leer su contenido completo

### Notificaciones

Si recibes un mensaje nuevo mientras usas la app, aparece un banner de notificación en la parte superior de la pantalla. Toca el banner para abrir el panel de mensajes directamente.

Los mensajes pueden incluir un enlace a una ubicación de navegación. En ese caso verás un botón **Navegar** que añade ese destino directamente al planificador de rutas.

---

## Vista de satélites GPS

Toca el **icono de satélite** para abrir la vista de satélites. Muestra:

- **Vista polar acimutal**: posición de cada satélite en el cielo (azimut y elevación)
- **Barras de señal SNR**: intensidad de señal de cada satélite
- **Estado del fix**: sin señal / fix 2D / fix 3D
- **Número de satélites**: visibles y en uso

Útil para diagnosticar problemas de recepción o comparar señal en distintos lugares.

---

## Grabación de tracks

Navius puede grabar tu trayecto GPS en tiempo real.

### Activar grabación

Activa **Grabar track** en **Ajustes → Navegación**. La grabación comienza cuando hay fix GPS y se detiene al desactivarla o cerrar la app.

### Ver y exportar tracks

Los tracks grabados se muestran en **Ajustes → Navegación → Tracks grabados**:

- **Ver en mapa**: muestra el recorrido en el mapa
- **Exportar GPX**: guarda el track en formato GPX estándar en `~/.local/share/navius.woodyst/gps_tracks/`
- **Simular**: reproduce el track como ruta de simulación GPS
- **Eliminar**: borra el track de la base de datos

---

## Servidor Valhalla y tráfico

### Servidor oficial

Navius usa por defecto el servidor **valhalla.egpsistemas.com**, que ofrece:

- **Cobertura mundial**: el planeta completo con datos de OpenStreetMap
- **Tráfico predicho**: perfiles de velocidad por hora del día y día de la semana en toda la red viaria
- **Todos los vehículos**: coche, moto, camión, bicicleta, a pie, ciclomotor y más
- **Sin límites**: sin restricciones de uso para usuarios de Navius

### Tráfico predicho

El tráfico predicho permite a Valhalla ajustar los tiempos de viaje según el momento del día. Por ejemplo:

- Una autopista puede tener 115 km/h en hora libre y 85 km/h en hora punta
- Una calle urbana puede tener 45 km/h por la noche y 25 km/h en hora punta

Navius envía siempre la hora actual o la hora de salida programada al servidor para que aplique el perfil correcto.

### Servidor propio

Puedes usar tu propio servidor Valhalla. Configura la URL en **Ajustes → Servidor Valhalla**. Útil para:

- Privacidad total (ningún dato sale del dispositivo)
- Trabajo sin internet
- Datos cartográficos personalizados

### Mapas offline con OSM Scout Server

Instala **OSM Scout Server** desde la OpenStore de Ubuntu Touch para calcular rutas y buscar lugares completamente sin conexión a internet. Los mapas y datos de routing se descargan al dispositivo.

Navius detecta automáticamente si OSM Scout Server está en ejecución. Actívalo desde **Ajustes → Servidor Valhalla → Detectar servidor local** o espera a que Navius lo detecte al arrancar.

---

## Ajustes

El panel de ajustes se abre con el botón **⚙ Ajustes** del menú **≡**. Es el 7.º ítem del menú (tras Mensajes y las opciones de Parking).

### Nivel de opciones

El panel de ajustes tiene un selector de nivel en la parte superior:

| Nivel | Descripción |
|-------|-------------|
| **Mínimo** | Solo opciones esenciales. Recomendado para la mayoría de usuarios |
| **Medio** | Opciones adicionales de navegación y comportamiento GPS |
| **Avanzado** | Todas las opciones, incluyendo configuración técnica y de depuración |

Las secciones y opciones que no corresponden al nivel seleccionado se ocultan automáticamente para simplificar el panel.

### Controles [−] [+] en lugar de sliders

Los valores numéricos (Hz de interpolación, distancias, tiempos…) se ajustan con botones **[−]** y **[+]** en lugar de sliders. Esto evita cambios accidentales al hacer scroll por el panel.

### Indicador de valor por defecto ↺

Junto a cada opción que tiene un valor por defecto diferente al actual, se muestra el valor por defecto con un símbolo **↺** (por ejemplo: `↺ 8 m`, `↺ 15 s`, `↺ act.`). Si el valor ya es el predeterminado, el indicador no aparece.

### Restaurar valores por defecto

En la parte superior del panel de ajustes hay un botón **↺ Restaurar valores por defecto**.

- Al tocarlo por primera vez aparece un mensaje de confirmación
- Debes tocarlo **una segunda vez** para confirmar (doble toque de seguridad)
- Si no confirmas en 3 segundos, la confirmación se cancela automáticamente
- Al confirmar, todos los ajustes vuelven a sus valores de fábrica

### Ajustes rápidos

Opciones frecuentes accesibles sin abrir secciones:

- Modo de color del mapa (día/noche/auto)
- Zoom automático (ajusta el zoom según la velocidad)
- Orientación del mapa (norte fijo o siguiendo el rumbo)

### General

- Interpolación GPS (dead-reckoning) a 10/20/30 Hz
- Alerta de velocidad (umbral de aviso)
- **Mostrar velocidad máxima de la vía** — usa el límite OSM de la carretera como fuente de alerta de velocidad. Desactivado por defecto (cobertura no fiable en OSM).
- **Inhibir suspensión durante navegación** — evita que la pantalla se apague mientras navegas (activado por defecto).
- **Escala de texto global** — ajusta el tamaño de todo el texto de la app (rango 0,8–1,5).
- Posición manual (útil para pruebas sin GPS)

### Servidor Valhalla

- URL del servidor de rutas
- Opción de detección automática de servidor local (OSM Scout)

### Navegación

- **Tipo de vehículo** — selecciona el vehículo activo o abre el gestor de vehículos para crear/renombrar/eliminar vehículos propios con alias y tipo (coche, moto, bicicleta, a pie, camión…). El vehículo activo también determina qué posición de aparcamiento se usa.
- **Velocidad GPS Doppler** — usa la velocidad del chip GPS (efecto Doppler) en vez de calcularla por diferencia de posiciones. Más precisa a baja velocidad y en aceleraciones; desactiva si observas velocidades erráticas en tu dispositivo.
- Grabación de tracks GPS
- Gestión de tracks grabados

### Billboards (carteles publicitarios)

Durante la navegación pueden aparecer carteles publicitarios virtuales en el mapa, situados junto a las vías. Cuando te acercas a menos de 600 m de un cartel, aparece brevemente un panel bajo la barra de navegación con el título y descripción del anuncio.

- Toca el panel para abrir la web del anunciante en el navegador
- El panel se cierra automáticamente a los 12 segundos
- El mismo cartel no vuelve a aparecer hasta pasados 60 segundos
- También puedes tocar el cartel directamente en el mapa para abrir su enlace

Los anuncios son discretos y no interrumpen la navegación. Verlos y hacer click ayuda a financiar el desarrollo de Navius.

### Voz

- Motor TTS (Piper / Mimic HTS / PicoTTS)
- Idioma de las instrucciones
- Selección de voz
- Descarga de voces Piper
- Test de voz

### Ayuda

- Manual de usuario (esta documentación)
- Asistente de bienvenida
- Opción "Mostrar asistente al inicio"
- Acerca de Navius

---

## Datos y privacidad

Navius almacena los siguientes datos **solo en el dispositivo**:

| Dato | Ubicación |
|------|-----------|
| Tracks GPS grabados | `~/.local/share/navius.woodyst/gps_tracks.db` |
| GPX exportados | `~/.local/share/navius.woodyst/gps_tracks/` |
| Favoritos, historial, preferencias | `~/.local/share/navius.woodyst/QtProject/` |
| TODOs por destino | SQLite LocalStorage (QtProject) |
| Planes de viaje guardados | Settings (QtProject) |

Las búsquedas de lugares se envían al geocodificador **Photon/Komoot** (OpenStreetMap). El cálculo de rutas se envía al servidor Valhalla configurado.

Si usas un servidor Valhalla propio, ningún dato sale del dispositivo.
