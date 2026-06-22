# Filosofía de Navius

## Por qué existe

Navius no es el resultado de un análisis de mercado ni de una oportunidad de negocio. Es el resultado de años de frustración con navegadores que no respetan al usuario.

Durante años probé todos los navegadores GPS disponibles para Android y UbPorts. Ninguno me daba lo que necesitaba:

**Google Maps / Navigation** — El mejor en cálculo de tráfico y búsqueda de destinos, pero sin control sobre la interfaz, sin alertas comunitarias reales, y con un modelo de negocio basado en saber dónde estás en cada momento de tu vida.

**Waze** — Comunidad activa, pero propiedad de Google desde 2013, invasivo por diseño, y con peor cálculo de tráfico que su empresa matriz.

**OsmAnd / Maps.me** — Privacidad real y software libre, pero sin alertas comunitarias en tiempo real, con interfaces difíciles o desactualizadas, y sin las características profesionales que necesitaba.

**uNav / Pure Maps (UbPorts)** — Opciones respetables para la plataforma, pero sin alertas comunitarias, sin tráfico predicho, y con movimiento del vehículo poco fluido.

La conclusión fue simple: el navegador que necesitaba no existía. Así que lo construí.

Al mismo tiempo, el hartazgo con el ecosistema Android cerrado y con vivir sujeto a los intereses de corporaciones que tratan a sus usuarios como producto me llevó a dar el salto a UbPorts. Navius nació primero para ese sistema, y es el GPS que siempre quise tener.

---

## Valores fundamentales

Navius nace de los valores del software libre tal como los defiende la FSF. **Privacidad, control del usuario, transparencia y comunidad no son características opcionales: son los principios de diseño.**

- **Privacidad por diseño:** Las rutas y el historial quedan en el dispositivo. Sin telemetría, sin perfiles de usuario, sin venta de datos a terceros.
- **Control real:** El usuario puede usar su propio servidor Valhalla o funcionar completamente offline con OSM Scout. Ninguna función esencial depende de un servicio propietario.
- **Comunidad abierta:** Las alertas de tráfico, radares y peligros son para todos los usuarios, y cualquiera puede contribuir.
- **Transparencia:** Cómo funciona el modelo económico se explica abiertamente. No hay letra pequeña.

---

## Dos versiones, un mismo proyecto

Navius tiene un componente pragmático que hay que explicar con honestidad: **la versión Android no es software libre y contiene publicidad**. Esto no es una contradicción: es una decisión consciente.

### Navius para UbPorts — Software libre, siempre gratuito

- Código abierto bajo licencia GPL
- Sin publicidad, sin suscripción, sin telemetría
- Financiado por donaciones y por el trabajo que genera la versión Android
- Es el producto que refleja plenamente los valores del proyecto

### Navius para Android — Propietario, con publicidad o bien suscripción

- Código propietario (no publicado)
- Publicidad no invasiva (billboards geo-referenciados que no interrumpen la navegación)
- Suscripción Premium opcional para eliminar publicidad y añadir funciones
- Es el motor económico que hace posible el proyecto entero

### Por qué este modelo

Hay una tensión real entre vivir del software libre y que ese software sea libre. Resolverla con honestidad es más importante que resolverla con pureza.

La alternativa —hacer la versión Android completamente libre sin fuente de ingresos— significaría que el proyecto moriría o pasaría a ser un hobby sin mantenimiento activo. Eso no sirve ni a los usuarios de UbPorts ni a nadie.

El modelo elegido es transparente: UbPorts libre siempre, porque es la plataforma de los usuarios que comparten los valores del proyecto. Android propietario con publicidad discreta, porque es donde está la masa crítica de usuarios y el único lugar viable para generar ingresos.

### Lo que no cambia en ninguna versión

- Las rutas y el historial quedan en el dispositivo
- El servidor comunitario y las alertas son para todos los usuarios
- La publicidad no interrumpe la navegación
- Nunca se venderán datos de ubicación a anunciantes

---

## Posición frente a otras alternativas

| Característica | Google Maps | Waze | OsmAnd | Pure Maps | uNav | Navius |
|---|---|---|---|---|---|---|
| Privacidad real | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| Alertas comunitarias | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| Software libre (UbPorts) | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| Servidor propio | ❌ | ❌ | ❌ | Parcial | ❌ | ✅ |
| Offline completo | Caché | Caché | ✅ | Con plugin | ❌ | ✅ |
| Tráfico predicho | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| Sincronización multidevice | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| Compartir viaje en tiempo real | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| UbPorts / Linux móvil | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |

**Navius es el único GPS que combina privacidad real con alertas comunitarias.** El resto de características refuerzan esa propuesta: tráfico predicho, servidor propio, funcionamiento offline, TODOs por destino, compartir viaje. El nicho "Waze privado y libre" no tiene competidor directo.

---

## Cómo se financia el proyecto

La monetización existe para pagar el trabajo. No compromete la privacidad. Se declara abiertamente.

- **Donaciones (Liberapay):** Para usuarios de UbPorts y para quien quiera apoyar directamente. Financian el servidor Valhalla, el servidor comunitario y las horas de mantenimiento.
- **Publicidad en Android:** Billboards geo-referenciados, no invasivos. La navegación no se interrumpe. El mismo cartel no repite en 60 segundos.
- **Suscripción Premium (Android):** Opción para eliminar publicidad y acceder a funciones adicionales.

Periódicamente se publican balances de transparencia con número de usuarios, ingresos por fuente y gastos del proyecto. Esto construye la confianza que un proyecto como este necesita: la comunidad ha sido traicionada repetidamente por apps "gratuitas".

---

## Visión a largo plazo

El objetivo no es solo vivir de Navius. Es construir una fuente de ingresos estable basada en proyectos de software libre que respeten al usuario. Navius es el primero. No tiene por qué ser el único.

El modelo que funciona para desarrolladores independientes de software libre es el de **portafolio**, no el de **producto único**: varios proyectos que se sostienen mutuamente, con la consultoría y los contratos relacionados con el stack tecnológico como complemento.

El objetivo inmediato es modesto: que el proyecto cubra sus costes y permita dedicarle el tiempo que merece. El objetivo a largo plazo es más ambicioso: demostrar que se puede construir software útil, privado y libre sin depender de corporaciones ni de inversores.

---

*"No busco competir con Google. Busco que haya un GPS que no te espíe. Si podemos vivir de ello, mejor para todos."*

---

[← Volver al README](../README.es.md) · [Manual de usuario](user.es.md) · [Guía del desarrollador](developer.es.md)
