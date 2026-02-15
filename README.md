# Teoría Completa de la Base de Datos de Moodle
## Guía exhaustiva de tablas, relaciones y conceptos

> **Versión:** Moodle 4.3+ / 5.x
> **Motor:** MySQL / MariaDB
> **Prefijo por defecto:** `mdl_`
> **Formato de fechas:** Todas las fechas se almacenan como UNIX timestamps (segundos desde 1970-01-01). Usar `FROM_UNIXTIME()` para convertir.

---

# PARTE 1: ARQUITECTURA GENERAL

## 1.1 Filosofía de diseño de Moodle

Moodle utiliza un diseño de base de datos **sin foreign keys reales** a nivel de motor (InnoDB no las impone). Las relaciones existen a nivel lógico, mantenidas por el código PHP de Moodle. Esto da flexibilidad pero significa que:

- No hay CASCADE DELETE automático.
- Pueden existir registros huérfanos si se manipula la BD directamente.
- La integridad referencial la mantiene la aplicación, no la base de datos.

Moodle organiza sus tablas en **grupos funcionales**. Un módulo de actividad (quiz, assign, forum...) tiene sus propias tablas prefijadas con su nombre (mdl_quiz, mdl_quiz_attempts, etc.), y todas se relacionan con las tablas "core" a través de unas pocas tablas puente clave.

## 1.2 Las 4 tablas "columna vertebral"

Hay 4 tablas que conectan prácticamente todo en Moodle:

```
mdl_user          → El QUIÉN (personas)
mdl_course        → El DÓNDE (cursos)
mdl_context       → El ÁMBITO (dónde se aplican permisos)
mdl_course_modules → El QUÉ (actividades dentro de cursos)
```

Si entiendes estas 4 tablas y cómo se relacionan, entiendes el 80% de Moodle.

## 1.3 Convenciones de la base de datos

- **`id`**: Siempre es la PRIMARY KEY autoincremental de cada tabla.
- **`timecreated` / `timemodified`**: UNIX timestamps.
- **`deleted`**: Flag booleano (0/1). Moodle hace "soft delete" en muchas tablas.
- **`suspended`**: Flag booleano para desactivar sin eliminar.
- **`visible`**: Flag booleano para ocultar elementos.
- **`sortorder`**: Entero para definir orden de visualización.

---

# PARTE 2: USUARIOS

## 2.1 `mdl_user` — Tabla principal de usuarios

Es la tabla más referenciada de toda la base de datos. Prácticamente todas las demás tablas tienen algún campo `userid` que apunta aquí.

**Columnas clave:**
- `id`: PK. Referenciada como `userid` en cientos de tablas.
- `username`: Nombre de usuario único para login.
- `password`: Hash bcrypt de la contraseña.
- `auth`: Método de autenticación ('manual', 'ldap', 'oauth2', etc.).
- `confirmed`: Si el usuario ha confirmado su cuenta por email (0/1).
- `deleted`: **Soft delete**. Si es 1, el usuario se considera eliminado pero el registro permanece. Moodle limpia sus datos personales pero mantiene la fila.
- `suspended`: Usuario desactivado pero no eliminado.
- `firstname`, `lastname`, `email`: Datos personales básicos.
- `firstaccess`: Timestamp del primer login. Si es 0, el usuario nunca ha entrado.
- `lastaccess`: Timestamp del último login.
- `lastlogin` / `currentlogin`: Controlan la sesión actual y la anterior.

**Concepto importante: usuario `guest` (id=1 normalmente) y usuario `admin` (id=2 normalmente).** El admin se define en `mdl_config` con la clave `siteadmins` (lista de IDs separados por comas). No es un rol, es una configuración del sistema.

**Relación con "deleted":** Siempre que hagas queries sobre usuarios, incluye `WHERE u.deleted = 0`. Los usuarios eliminados dejan "fantasmas" en la base de datos con datos personales borrados pero el ID intacto, para mantener la integridad de calificaciones y logs históricos.

## 2.2 `mdl_user_info_field` y `mdl_user_info_data` — Perfil personalizado

Moodle permite crear campos de perfil extra (DNI, departamento, teléfono corporativo, etc.).

- **`mdl_user_info_field`**: Define los campos (nombre, tipo, categoría). Es la "plantilla".
- **`mdl_user_info_data`**: Almacena los valores para cada usuario.

```
mdl_user_info_field (fieldid)  ←  mdl_user_info_data  →  mdl_user (userid)
```

La relación es: un campo (`field`) puede tener muchos valores (`data`), uno por cada usuario que lo rellene.

## 2.3 `mdl_user_preferences` — Preferencias del usuario

Almacena configuraciones individuales en formato clave-valor. Ejemplos:
- `auth_forcepasswordchange`: Si se le obliga a cambiar contraseña.
- `htmleditor`: Qué editor WYSIWYG prefiere.
- `email_bounce_count`: Contador de emails rebotados.

Es una tabla de tipo **EAV** (Entity-Attribute-Value): cada fila es un par nombre/valor para un usuario.

## 2.4 `mdl_sessions` — Sesiones activas

Cada fila representa una sesión activa de un usuario. Cuando un usuario hace login, se crea un registro aquí. Cuando cierra sesión o expira, se elimina.

- `userid` → `mdl_user.id`
- `sid`: Session ID del navegador (cookie).
- `timecreated`: Cuándo se creó la sesión.
- `timemodified`: Última actividad. Si `NOW() - timemodified > timeout`, la sesión está inactiva.

---

# PARTE 3: CURSOS Y CATEGORÍAS

## 3.1 `mdl_course_categories` — Categorías de cursos

Las categorías son **jerárquicas** (pueden tener subcategorías). La jerarquía se controla con:

- `parent`: ID de la categoría padre. Si es 0, es una categoría raíz.
- `depth`: Profundidad en el árbol (1 = raíz, 2 = subcategoría, etc.).
- `path`: Ruta completa. Ejemplo: `/1/3/7` = Raíz(1) → Cat(3) → SubCat(7).
- `sortorder`: Orden de visualización.
- `coursecount`: Contador de cursos (se actualiza automáticamente).

**Autoreferencia:** La tabla se referencia a sí misma a través de `parent`, formando un árbol.

## 3.2 `mdl_course` — Tabla de cursos

Cada fila es un curso. El curso con `id = 1` es especial: es la **Front Page** (página principal del sitio). Por eso muchas queries llevan `WHERE c.id > 1`.

**Columnas clave:**
- `category` → `mdl_course_categories.id` (la categoría a la que pertenece).
- `fullname`: Nombre completo del curso.
- `shortname`: Nombre corto (único en el sitio).
- `idnumber`: Identificador externo (para integración con otros sistemas).
- `format`: Tipo de formato del curso ('topics', 'weeks', 'social', etc.).
- `startdate` / `enddate`: Periodo del curso (timestamps).
- `visible`: Si el curso está visible para los estudiantes.
- `enablecompletion`: Si el seguimiento de completitud está habilitado.

**Relación con categorías:**
```
mdl_course_categories (id) ← mdl_course.category
        ↑ parent
        │ (autoreferencia para subcategorías)
```

## 3.3 `mdl_course_sections` — Secciones/temas del curso

Cada curso se divide en secciones (temas o semanas según el formato). Cada sección es un contenedor para actividades.

- `course` → `mdl_course.id`
- `section`: Número de sección (0 = sección general/cabecera, 1, 2, 3...).
- `name`: Nombre personalizado (si es NULL, se muestra "Tema X" o "Semana X").
- `summary`: Descripción/resumen de la sección.
- `sequence`: **Lista ordenada de IDs de `mdl_course_modules`** separados por comas. Define el orden de las actividades dentro de la sección.
- `visible`: Si la sección está visible.

**Concepto importante:** El campo `sequence` es una lista como "5,8,12,3". Ese orden determina cómo aparecen las actividades en el curso. Es una desnormalización intencional por rendimiento.

## 3.4 `mdl_modules` — Catálogo de tipos de actividad

Es una tabla pequeña de referencia que lista todos los **tipos** de módulos de actividad instalados en Moodle.

- `name`: Nombre del módulo ('assign', 'quiz', 'forum', 'resource', 'scorm', etc.).
- `visible`: Si el tipo de módulo está habilitado en el sitio.

No almacena instancias, solo el catálogo de tipos disponibles.

## 3.5 `mdl_course_modules` — Instancias de actividades en cursos

Esta es una de las tablas más importantes. Cada fila representa una actividad o recurso **concreto** dentro de un curso. Es la tabla puente entre el curso y la tabla específica de la actividad.

**Columnas clave:**
- `course` → `mdl_course.id`
- `module` → `mdl_modules.id` (qué tipo de actividad es: quiz, assign, forum...).
- `instance`: ID de la fila en la tabla específica del módulo.
- `section` → `mdl_course_sections.id`
- `visible`: Si la actividad está visible.
- `completion`: Tipo de seguimiento (0=ninguno, 1=manual, 2=automático).
- `added`: Timestamp de cuándo se añadió.

**El truco de `instance`:** El campo `instance` apunta a la tabla específica del módulo. Si `module` = ID de 'quiz', entonces `instance` apunta a `mdl_quiz.id`. Si `module` = ID de 'assign', apunta a `mdl_assign.id`.

```
                    mdl_modules (id, name='quiz')
                         ↑
mdl_course ← mdl_course_modules (course, module, instance) → mdl_quiz (id)
                         ↓
                    mdl_course_sections (id)
```

Esto significa que para saber el nombre de una actividad, necesitas:
1. Mirar `module` para saber el tipo (quiz, assign...).
2. Mirar `instance` para buscar en la tabla correspondiente.

## 3.6 `mdl_course_modules_completion` — Completitud de actividades

Registra si un usuario ha completado cada actividad.

- `coursemoduleid` → `mdl_course_modules.id`
- `userid` → `mdl_user.id`
- `completionstate`: Estado de completitud.
  - 0 = No completado
  - 1 = Completado (sin nota)
  - 2 = Completado - Aprobado
  - 3 = Completado - Suspendido

Solo existen registros para actividades que tienen seguimiento habilitado (`mdl_course_modules.completion > 0`).

## 3.7 `mdl_course_completions` — Completitud del curso completo

Diferente de la anterior. Esta tabla registra cuándo un **curso entero** se marca como completado.

- `userid` → `mdl_user.id`
- `course` → `mdl_course.id`
- `timecompleted`: Timestamp de cuándo se completó. Si es NULL, aún no se ha completado.
- `reaggregate`: Timestamp que indica cuándo se debe recalcular.

La completitud del curso se basa en criterios configurados (completar X actividades, obtener X nota, etc.). El cron de Moodle evalúa periódicamente si se cumplen los criterios.

---

# PARTE 4: EL SISTEMA DE CONTEXTOS

## 4.1 `mdl_context` — La tabla más abstracta pero más crucial

El sistema de contextos es el **mecanismo central de permisos** de Moodle. Un contexto define un "ámbito" o "lugar" donde se aplican roles y permisos.

**Columnas:**
- `contextlevel`: Tipo de ámbito (constante numérica).
- `instanceid`: ID del objeto al que pertenece (su significado depende del contextlevel).
- `path`: Ruta jerárquica completa.
- `depth`: Profundidad en la jerarquía.

**Valores de `contextlevel`:**

| contextlevel | Constante PHP | Qué representa | `instanceid` apunta a |
|:---:|---|---|---|
| 10 | CONTEXT_SYSTEM | Todo el sitio | Siempre `0` |
| 30 | CONTEXT_USER | Un usuario concreto | `mdl_user.id` |
| 40 | CONTEXT_COURSECAT | Una categoría | `mdl_course_categories.id` |
| 50 | CONTEXT_COURSE | Un curso | `mdl_course.id` |
| 70 | CONTEXT_MODULE | Una actividad | `mdl_course_modules.id` |
| 80 | CONTEXT_BLOCK | Un bloque | `mdl_block_instances.id` |

**Concepto fundamental: `instanceid` es un campo comodín.** Su significado cambia totalmente según el `contextlevel`. Solo cuando `contextlevel = 70` se refiere a una actividad. Cuando es 50, se refiere a un curso. Cuando es 30, a un usuario. Esto es una forma de **polimorfismo a nivel de base de datos**.

## 4.2 La jerarquía de contextos y el campo `path`

Los contextos forman un **árbol jerárquico**:

```
CONTEXT_SYSTEM (10)  ← Raíz, siempre path="/1"
├── CONTEXT_USER (30)  ← Cuelga directamente del sistema
├── CONTEXT_COURSECAT (40)
│   ├── CONTEXT_COURSECAT (40)  ← Subcategorías
│   │   └── CONTEXT_COURSE (50)
│   │       ├── CONTEXT_MODULE (70)
│   │       └── CONTEXT_BLOCK (80)
│   └── CONTEXT_COURSE (50)
└── CONTEXT_BLOCK (80)  ← Bloques del dashboard/sistema
```

El campo `path` codifica toda la jerarquía. Ejemplo con datos reales:

| context.id | contextlevel | instanceid | path | Significado |
|:---:|:---:|:---:|---|---|
| 1 | 10 (Sistema) | 0 | /1 | Raíz del sistema |
| 3 | 40 (Categoría) | 1 | /1/3 | Categoría id=1, hija del sistema |
| 21 | 40 (Categoría) | 2 | /1/3/21 | Subcategoría id=2, hija de la categoría anterior |
| 24 | 50 (Curso) | 2 | /1/3/21/24 | Curso id=2, dentro de esa subcategoría |
| 27 | 70 (Módulo) | 2 | /1/3/21/24/27 | Actividad (course_module id=2) dentro de ese curso |

**¿Para qué sirve path?** Para la **herencia de permisos**. Si un usuario tiene rol de "manager" en el contexto con path `/1/3`, ese rol se hereda automáticamente en todos los contextos cuyo path empiece por `/1/3/...` (todos los cursos y actividades de esa categoría y sus subcategorías).

Moodle usa consultas `LIKE` sobre el path para resolver la herencia:
```sql
WHERE ctx.path LIKE '/1/3/%'  -- Todo lo que cuelga de la categoría
```

## 4.3 ¿Por qué `mdl_context` es obligatoria para consultar roles?

La tabla `mdl_role_assignments` (quién tiene qué rol) **no tiene columna `courseid`**. Solo tiene `contextid`. Así que la única forma de saber "¿quién es profesor en el curso X?" es:

```
mdl_course.id = X
    ↓ (buscar contexto donde contextlevel=50 AND instanceid=X)
mdl_context.id = Y
    ↓ (buscar asignaciones donde contextid=Y)
mdl_role_assignments (roleid, userid)
    ↓
mdl_role (shortname='editingteacher')
```

No hay atajo. Siempre necesitas pasar por `mdl_context` para conectar roles con cursos.

---

# PARTE 5: ROLES Y PERMISOS

## 5.1 `mdl_role` — Definición de roles

Tabla pequeña con los roles disponibles en el sistema.

**Roles por defecto de Moodle:**

| id | shortname | archetype | Descripción |
|:---:|---|---|---|
| 1 | manager | manager | Gestores del sitio (casi admin) |
| 2 | coursecreator | coursecreator | Pueden crear cursos |
| 3 | editingteacher | editingteacher | Profesor con edición (puede modificar el curso) |
| 4 | teacher | teacher | Profesor sin edición (puede calificar pero no modificar estructura) |
| 5 | student | student | Estudiante |
| 6 | guest | guest | Invitado (acceso limitado sin cuenta) |
| 7 | user | user | Usuario autenticado (rol base de todos) |
| 8 | frontpage | frontpage | Rol especial para la página principal |

**`archetype`**: Define el "modelo base" del rol. Cuando se instala un nuevo plugin, Moodle asigna permisos por defecto a cada rol según su archetype. Un rol personalizado puede basarse en un archetype existente.

## 5.2 `mdl_role_assignments` — Quién tiene qué rol y dónde

Esta tabla es el corazón de la asignación de permisos.

| Columna | Pregunta que responde | Apunta a |
|---|---|---|
| `userid` | ¿QUIÉN? | `mdl_user.id` |
| `roleid` | ¿QUÉ ROL? | `mdl_role.id` |
| `contextid` | ¿DÓNDE? | `mdl_context.id` |

**Conceptos clave:**

1. **Un usuario puede tener DIFERENTES roles en DIFERENTES contextos.** Ejemplo: estudiante en Curso A, profesor en Curso B, manager a nivel de sistema.

2. **Un usuario puede tener MÚLTIPLES roles en el MISMO contexto.** Aunque es poco común, es posible. Por ejemplo, ser tanto `teacher` como `editingteacher` en el mismo curso.

3. **Los roles se heredan hacia abajo en la jerarquía de contextos.** Si eres `manager` en una categoría, automáticamente tienes ese rol en todos los cursos de esa categoría sin necesidad de asignación explícita.

4. **`component` e `itemid`**: Indican qué componente hizo la asignación. Si están vacíos, fue manual. Si `component = 'enrol_manual'`, fue por matriculación manual.

## 5.3 `mdl_role_capabilities` — Los permisos de cada rol

Define qué puede hacer cada rol. Es el "libro de reglas".

**Columnas:**
- `roleid` → `mdl_role.id`
- `contextid` → `mdl_context.id`
- `capability`: El permiso específico (string como 'mod/assign:submit', 'moodle/course:update').
- `permission`: Valor numérico del permiso.

**Valores de `permission`:**

| Valor | Significado | Descripción |
|:---:|---|---|
| 1 | **ALLOW** (CAP_ALLOW) | Permitido |
| 0 | **NOT SET** (CAP_INHERIT) | No definido (se hereda) |
| -1 | **PREVENT** (CAP_PREVENT) | Prevenido (se puede sobrescribir) |
| -1000 | **PROHIBIT** (CAP_PROHIBIT) | Prohibido absoluto (NO se puede sobrescribir) |

**¿Por qué casi todo tiene `contextid = 1` (sistema)?**

Porque `mdl_role_capabilities` almacena la **definición base/por defecto** de los permisos de cada rol, y esa definición se hace siempre a nivel de sistema. Todos los permisos que ves con `contextid=1` son la configuración estándar.

Solo aparecerían otros `contextid` cuando un administrador o profesor haga un **override** (sobrescritura) de permisos en un contexto específico. Ejemplo: "En este curso concreto, los estudiantes NO pueden subir archivos al foro". Eso crearía una fila con el `contextid` de ese curso y `permission = -1`.

**Formato de capabilities:**

Las capabilities siguen el formato `componente:acción`:
- `moodle/course:update` — Actualizar un curso (core de Moodle).
- `mod/assign:submit` — Enviar una tarea (módulo assign).
- `mod/quiz:attempt` — Intentar un cuestionario (módulo quiz).
- `block/html:addinstance` — Añadir un bloque HTML.
- `enrol/manual:enrol` — Matricular manualmente.

## 5.4 Cómo Moodle resuelve permisos (algoritmo)

Cuando Moodle necesita saber si un usuario puede hacer algo:

1. Recoge TODAS las role_assignments del usuario en el contexto actual y sus padres.
2. Para cada rol asignado, busca la capability en `role_capabilities`.
3. Aplica la jerarquía: si hay un PROHIBIT en cualquier nivel, gana PROHIBIT.
4. Si no, si hay un ALLOW en algún nivel y no hay PREVENT por debajo, se permite.
5. Si no hay nada definido, se deniega.

---

# PARTE 6: MATRICULACIÓN (ENROLMENT)

## 6.1 Concepto dual: Matriculación vs. Asignación de rol

Moodle separa dos conceptos que a menudo se confunden:

- **Matriculación** (`enrol` + `user_enrolments`): ¿El usuario está inscrito en el curso? ¿Con qué método?
- **Asignación de rol** (`role_assignments` + `context`): ¿Qué rol tiene en ese curso?

Normalmente van juntos (al matricular a alguien, se le asigna un rol), pero son tablas independientes. Esto permite situaciones como:
- Un usuario matriculado pero sin rol activo (raro pero posible).
- Un usuario con rol en un curso pero sin matriculación formal (más raro aún).

## 6.2 `mdl_enrol` — Métodos de matriculación configurados

Cada curso puede tener **varios métodos de matriculación** configurados simultáneamente.

- `enrol`: Tipo de método ('manual', 'self', 'cohort', 'guest', 'meta', etc.).
- `courseid` → `mdl_course.id`
- `status`: 0=activo, 1=deshabilitado.
- `roleid` → `mdl_role.id`: Rol por defecto que se asigna al matricularse con este método.

**Tipos comunes de enrolment:**

| enrol | Descripción |
|---|---|
| manual | Matriculación manual por profesor/admin |
| self | Auto-matriculación del estudiante (con o sin clave) |
| cohort | Sincronización con una cohorte |
| guest | Acceso como invitado |
| meta | Enlazado con otro curso (metacurso) |
| ldap | Sincronización con directorio LDAP |
| fee | Matriculación con pago |

**Un curso puede tener varias instancias del mismo método.** Por ejemplo, dos métodos 'self' con diferentes claves de acceso.

## 6.3 `mdl_user_enrolments` — Inscripciones de usuarios

La relación directa entre usuario y método de matriculación.

- `enrolid` → `mdl_enrol.id`
- `userid` → `mdl_user.id`
- `status`: 0=activo, 1=suspendido.
- `timestart` / `timeend`: Periodo de vigencia de la matrícula.
- `timecreated`: Cuándo se hizo la inscripción.

**Relación completa de matriculación:**
```
mdl_user ──→ mdl_user_enrolments ──→ mdl_enrol ──→ mdl_course
  (quién)       (inscripción)         (método)       (curso)
```

**Para saber quién está matriculado en un curso NO necesitas `mdl_context`:**
```
mdl_user → mdl_user_enrolments → mdl_enrol → mdl_course
```

**Para saber qué ROL tiene en ese curso SÍ necesitas `mdl_context`:**
```
mdl_user → mdl_role_assignments → mdl_context → mdl_course
                ↓
            mdl_role
```

---

# PARTE 7: CALIFICACIONES (GRADEBOOK)

## 7.1 Estructura general del Gradebook

El libro de calificaciones de Moodle tiene una estructura jerárquica:

```
mdl_grade_categories    (categorías de calificación)
    └── mdl_grade_items  (ítems/columnas del libro)
        └── mdl_grade_grades  (calificaciones individuales)
```

## 7.2 `mdl_grade_categories` — Categorías de calificación

Organizan los ítems de calificación en grupos con su propio método de agregación.

- `courseid` → `mdl_course.id`
- `fullname`: Nombre de la categoría (vacío = categoría del curso).
- `aggregation`: Método de cálculo.

**Valores de `aggregation`:**

| Valor | Método |
|:---:|---|
| 0 | Media de calificaciones |
| 10 | Media ponderada |
| 11 | Media ponderada simple |
| 12 | Media con créditos extra |
| 13 | Mediana |
| 2 | Calificación más baja |
| 4 | Calificación más alta |
| 6 | Suma de calificaciones |

Cada curso tiene automáticamente una categoría raíz (sin nombre) que agrupa todo.

## 7.3 `mdl_grade_items` — Ítems del libro de calificaciones

Cada ítem es una "columna" en el libro de calificaciones.

**Columnas clave:**
- `courseid` → `mdl_course.id`
- `categoryid` → `mdl_grade_categories.id`
- `itemtype`: Tipo de ítem.
  - `'course'` = Calificación total del curso (una por curso).
  - `'category'` = Total de una categoría.
  - `'mod'` = Calificación de una actividad.
  - `'manual'` = Ítem manual (añadido por el profesor).
- `itemmodule`: Si `itemtype='mod'`, nombre del módulo ('quiz', 'assign', etc.).
- `iteminstance`: Si `itemtype='mod'`, ID en la tabla del módulo (mdl_quiz.id, mdl_assign.id).
- `grademax` / `grademin`: Rango de calificación.
- `gradepass`: Nota de aprobado.

**Concepto importante:** Siempre existe un grade_item con `itemtype='course'` para cada curso. Es el que almacena la nota final del curso.

## 7.4 `mdl_grade_grades` — Las calificaciones individuales

Una fila por cada combinación usuario + ítem de calificación.

- `itemid` → `mdl_grade_items.id`
- `userid` → `mdl_user.id`
- `rawgrade`: Nota original tal como la envió la actividad.
- `rawgrademax` / `rawgrademin`: Escala original.
- `finalgrade`: Nota final después de aplicar la fórmula de agregación. **Esta es la nota "real" que se muestra.**
- `feedback`: Retroalimentación del profesor.

**¿rawgrade vs finalgrade?** La actividad envía `rawgrade` (ej: 8 sobre 10). Moodle recalcula `finalgrade` aplicando pesos, escalas y métodos de agregación de la categoría. `finalgrade` es la que importa.

## 7.5 `mdl_scale` — Escalas de calificación

Permiten calificar con texto en lugar de números. Ejemplo: "Insuficiente, Suficiente, Bien, Notable, Sobresaliente".

- `scale`: Los valores separados por comas: "Insuficiente,Suficiente,Bien,Notable,Sobresaliente".
- `courseid`: Si es 0 o NULL, es una escala global del sitio. Si tiene valor, es específica de un curso.

---

# PARTE 8: ACTIVIDADES PRINCIPALES

## 8.1 Patrón general de tablas por actividad

Cada módulo de actividad sigue un patrón similar:

```
mdl_[módulo]              → Configuración de la instancia
mdl_[módulo]_[subtabla]   → Datos específicos (intentos, entregas, etc.)
```

La relación con el sistema core es siempre a través de `mdl_course_modules`:
```
mdl_course_modules.module = mdl_modules.id (donde name='quiz')
mdl_course_modules.instance = mdl_quiz.id
```

## 8.2 Tareas (`mdl_assign`)

**`mdl_assign`** — Configuración de la tarea:
- `course` → `mdl_course.id`
- `name`: Nombre de la tarea.
- `duedate`: Fecha límite de entrega (timestamp).
- `cutoffdate`: Fecha de corte absoluta (después de esta, no se acepta nada).
- `allowsubmissionsfromdate`: Cuándo se abre.
- `grade`: Nota máxima. Si es negativa, usa una escala (valor = -ID de la escala).
- `teamsubmission`: Si es entrega grupal.

**`mdl_assign_submission`** — Entregas de estudiantes:
- `assignment` → `mdl_assign.id`
- `userid` → `mdl_user.id`
- `status`: 'new', 'draft', 'submitted', 'reopened'.
- `latest`: 1 si es la entrega más reciente (importante para filtrar).

**`mdl_assign_grades`** — Calificaciones de tareas:
- `assignment` → `mdl_assign.id`
- `userid` → `mdl_user.id` (estudiante).
- `grader` → `mdl_user.id` (profesor que calificó).
- `grade`: La nota. Si es -1, significa "sin calificar".

**Flujo de datos:**
```
Estudiante entrega → mdl_assign_submission (status='submitted')
Profesor califica  → mdl_assign_grades (grade=8.5)
                  → mdl_grade_grades (finalgrade=8.5) [automáticamente]
```

## 8.3 Cuestionarios (`mdl_quiz`)

**`mdl_quiz`** — Configuración del cuestionario:
- `course` → `mdl_course.id`
- `timeopen` / `timeclose`: Periodo de disponibilidad.
- `timelimit`: Límite de tiempo en segundos (0 = sin límite).
- `attempts`: Intentos permitidos (0 = ilimitados).
- `grademethod`: 1=más alta, 2=media, 3=primero, 4=último.
- `grade`: Nota máxima del cuestionario.
- `sumgrades`: Suma de los puntos de todas las preguntas.

**`mdl_quiz_attempts`** — Intentos de los estudiantes:
- `quiz` → `mdl_quiz.id`
- `userid` → `mdl_user.id`
- `attempt`: Número de intento (1, 2, 3...).
- `state`: 'inprogress', 'overdue', 'finished', 'abandoned'.
- `sumgrades`: Puntos obtenidos (no es la nota final).
- `timestart` / `timefinish`: Cuándo empezó y terminó.

**Cálculo de la nota:** La nota del cuestionario se calcula como:
```
nota = (sumgrades / quiz.sumgrades) * quiz.grade
```
Ejemplo: si el quiz tiene 20 puntos posibles (`sumgrades=20`), nota máxima 10 (`grade=10`), y el alumno obtiene 15 puntos, su nota es `(15/20)*10 = 7.5`.

**`mdl_question`** — Banco de preguntas:
- `questiontext`: Texto de la pregunta.
- `qtype`: Tipo ('multichoice', 'truefalse', 'shortanswer', 'essay', 'numerical', etc.).
- `category`: Categoría del banco de preguntas (NO es mdl_course_categories).

**`mdl_question_answers`** — Opciones de respuesta:
- `question` → `mdl_question.id`
- `answer`: Texto de la opción.
- `fraction`: Proporción de corrección (1.0 = totalmente correcta, 0 = incorrecta, 0.5 = parcial).

## 8.4 Foros (`mdl_forum`)

**`mdl_forum`** — Configuración del foro:
- `course` → `mdl_course.id`
- `type`: 'general', 'news', 'social', 'eachuser', 'qanda', 'blog'.

**`mdl_forum_discussions`** — Discusiones (hilos):
- `forum` → `mdl_forum.id`
- `course` → `mdl_course.id` (desnormalización por rendimiento).
- `userid` → `mdl_user.id` (creador).
- `name`: Título de la discusión.

**`mdl_forum_posts`** — Mensajes individuales:
- `discussion` → `mdl_forum_discussions.id`
- `userid` → `mdl_user.id` (autor).
- `parent`: ID del post al que responde. Si es 0, es el post inicial de la discusión.
- `message`: Contenido del mensaje.
- `created` / `modified`: Timestamps.

**Jerarquía de hilos:**
```
Forum → Discussions → Posts (con parent para crear árbol de respuestas)
                      ├── Post padre (parent=0)
                      │   ├── Respuesta 1 (parent=post_padre.id)
                      │   │   └── Respuesta a respuesta 1
                      │   └── Respuesta 2
```

## 8.5 SCORM (`mdl_scorm`) — Versión Moodle 4.3+/5.x

**Cambio importante en Moodle 4.3:** La antigua tabla `mdl_scorm_scoes_track` fue dividida en tres tablas nuevas para mejorar el rendimiento:

**`mdl_scorm`** — Configuración del paquete SCORM.

**`mdl_scorm_scoes`** — SCOs (Sharable Content Objects) del paquete.

**`mdl_scorm_attempt`** — Intentos:
- `userid` → `mdl_user.id`
- `scormid` → `mdl_scorm.id`
- `attempt`: Número de intento.

**`mdl_scorm_element`** — Catálogo de elementos CMI:
- `element`: Nombre del elemento ('cmi.core.lesson_status', 'cmi.core.score.raw', etc.).

**`mdl_scorm_scoes_value`** — Valores de tracking:
- `attemptid` → `mdl_scorm_attempt.id`
- `scoid` → `mdl_scorm_scoes.id`
- `elementid` → `mdl_scorm_element.id`
- `value`: Valor del dato.

**Relación nueva:**
```
mdl_scorm_attempt (userid + scormid + attempt)
    ↓ attemptid
mdl_scorm_scoes_value (valor real del dato)
    ↓ elementid              ↓ scoid
mdl_scorm_element         mdl_scorm_scoes
(nombre del elemento CMI)  (SCO del paquete)
```

La ventaja de esta normalización es que el nombre del elemento (que se repetía millones de veces) ahora se almacena una sola vez en `mdl_scorm_element`.

---

# PARTE 9: GRUPOS Y COHORTES

## 9.1 Grupos dentro de cursos

- **`mdl_groups`**: Grupos dentro de un curso (`courseid` → `mdl_course.id`).
- **`mdl_groups_members`**: Qué usuarios pertenecen a cada grupo (`groupid` → `mdl_groups.id`, `userid` → `mdl_user.id`).
- **`mdl_groupings`**: Agrupamientos = conjuntos de grupos. Permiten asignar actividades a un conjunto de grupos.
- **`mdl_groupings_groups`**: Qué grupos pertenecen a cada agrupamiento.

**Jerarquía:**
```
mdl_course
  └── mdl_groupings (agrupamientos)
  │     └── mdl_groupings_groups → mdl_groups
  └── mdl_groups (grupos)
        └── mdl_groups_members → mdl_user
```

Los grupos son **locales a un curso**. Un mismo usuario puede estar en diferentes grupos en diferentes cursos.

## 9.2 Cohortes (grupos globales)

A diferencia de los grupos, las cohortes son **globales al sitio** o a una categoría.

- **`mdl_cohort`**: Definición de la cohorte.
  - `contextid` → `mdl_context.id` (si apunta al contexto sistema = global; si apunta a una categoría = local a esa categoría).
  - `name`: Nombre de la cohorte.
- **`mdl_cohort_members`**: Miembros de la cohorte.

Las cohortes se usan típicamente para **automatizar matriculación**: "Todos los usuarios de la cohorte 'Departamento Ventas' se matriculan automáticamente en el curso 'Formación Ventas'".

---

# PARTE 10: MENSAJERÍA Y NOTIFICACIONES

## 10.1 Separación mensajes vs notificaciones

Desde Moodle 3.5+, mensajes y notificaciones son **completamente independientes**:

**Mensajes (comunicación entre usuarios):**
- **`mdl_messages`**: El mensaje en sí (`useridfrom`, `conversationid`, `fullmessage`, `timecreated`).
- **`mdl_message_conversations`**: Las conversaciones (`type`: 1=individual, 2=grupal, 3=self).
- **`mdl_message_conversation_members`**: Quién participa en cada conversación.
- **`mdl_message_user_actions`**: Acciones sobre mensajes (leído, eliminado).

**Notificaciones (sistema → usuario):**
- **`mdl_notifications`**: Notificaciones generadas por el sistema.
  - `useridfrom`: Quién la genera (puede ser un usuario o el sistema).
  - `useridto`: A quién va dirigida.
  - `subject`: Asunto.
  - `fullmessage` / `smallmessage`: Contenido.
  - `component`: Qué componente la generó ('mod_assign', 'mod_forum', etc.).
  - `eventtype`: Tipo de evento ('submission', 'grading', etc.).
  - `timeread`: NULL = no leída, timestamp = cuándo se leyó.

---

# PARTE 11: ARCHIVOS

## 11.1 `mdl_files` — Sistema de archivos de Moodle

Moodle NO almacena archivos con su nombre original en el disco. Usa un sistema basado en **content hash** (SHA1 del contenido).

**Columnas clave:**
- `contenthash`: Hash SHA1 del contenido. Archivos con el mismo contenido comparten el mismo hash (deduplicación).
- `component`: Qué componente "posee" el archivo ('mod_assign', 'user', 'course', etc.).
- `filearea`: Subárea dentro del componente ('submission', 'content', 'intro', 'draft', etc.).
- `contextid` → `mdl_context.id`: En qué contexto está el archivo.
- `filepath`: Ruta virtual (siempre empieza y termina con `/`).
- `filename`: Nombre original. Si es `.` (punto), es un directorio.
- `filesize`: Tamaño en bytes. Los directorios tienen `filesize = 0`.
- `userid` → `mdl_user.id`: Quién subió el archivo.
- `mimetype`: Tipo MIME del archivo.

**Concepto de deduplicación:** Si 50 estudiantes suben el mismo PDF, Moodle almacena UNA sola copia en disco (identificada por el `contenthash`) pero crea 50 filas en `mdl_files` con el mismo `contenthash`. Esto ahorra espacio.

**Archivos en disco:** Se almacenan en `$CFG->dataroot/filedir/` organizados por los dos primeros caracteres del hash:
```
filedir/ab/cd/abcd1234...   (archivo real, sin extensión)
```

**Filtrar directorios:** Siempre usa `WHERE filename <> '.' AND filesize > 0` para excluir los registros de directorio.

---

# PARTE 12: LOGS Y EVENTOS

## 12.1 `mdl_logstore_standard_log` — Log estándar de eventos

Es la tabla de auditoría principal de Moodle. Registra **toda** la actividad.

**Columnas clave:**
- `eventname`: Nombre completo del evento (`\core\event\user_loggedin`, `\mod_assign\event\submission_created`, etc.).
- `component`: Componente que generó el evento ('core', 'mod_quiz', 'mod_forum', etc.).
- `action`: La acción ('viewed', 'created', 'updated', 'deleted', 'submitted', 'graded', 'loggedin', etc.).
- `target`: Objetivo de la acción ('course', 'course_module', 'user', etc.).
- `userid` → `mdl_user.id`: Quién realizó la acción.
- `courseid` → `mdl_course.id`: En qué curso (0 si no aplica).
- `contextid` → `mdl_context.id`: Contexto exacto.
- `objecttable`: Tabla del objeto afectado.
- `objectid`: ID del objeto afectado.
- `ip`: Dirección IP del usuario.
- `timecreated`: Cuándo ocurrió.

**Es la tabla que más crece** en toda la base de datos. En sitios grandes puede tener millones de filas. Es importante tener una política de limpieza (rotación de logs).

**Existe también `mdl_log`** (log legacy) en Moodle antiguo, pero en versiones modernas solo se usa `logstore_standard_log`.

---

# PARTE 13: BLOQUES

## 13.1 `mdl_block_instances` — Instancias de bloques

Cada bloque visible en alguna página de Moodle tiene una fila aquí.

**Columnas clave:**
- `blockname`: Tipo de bloque ('html', 'calendar_month', 'online_users', etc.).
- `parentcontextid` → `mdl_context.id`: En qué contexto está colocado.
- `showinsubcontexts`: Si se muestra en contextos hijos (para bloques "sticky").
- `pagetypepattern`: En qué páginas se muestra ('course-view-*', 'my-index', 'site-index', '*', etc.).
- `defaultregion`: Región por defecto ('side-pre', 'side-post', etc.).
- `defaultweight`: Peso/posición por defecto.
- `configdata`: Configuración serializada del bloque (formato base64 de PHP serialize).

## 13.2 `mdl_block_positions` — Posición y visibilidad por página

Permite que un mismo bloque tenga diferente posición y visibilidad en diferentes páginas.

- `blockinstanceid` → `mdl_block_instances.id`
- `contextid` → `mdl_context.id`
- `pagetype`: Tipo de página específica.
- `visible`: Si está visible (0/1). **Este campo NO está en block_instances**, solo aquí.
- `region`: Región en esta página específica.
- `weight`: Peso/posición en esta página específica.

**Relación:** Un bloque sin registro en `block_positions` simplemente usa los valores por defecto de `block_instances`. Solo cuando se personaliza la posición o visibilidad en una página específica se crea un registro en `block_positions`.

---

# PARTE 14: CONFIGURACIÓN

## 14.1 `mdl_config` — Configuración global

Almacena toda la configuración general de Moodle en formato clave-valor.

- `name`: Nombre del parámetro.
- `value`: Valor del parámetro.

Ejemplos importantes:
- `siteadmins`: IDs de los administradores del sitio (separados por comas).
- `version`: Versión de Moodle instalada.
- `enablecompletion`: Si el seguimiento de completitud está habilitado globalmente.
- `maxbytes`: Tamaño máximo de subida de archivos.

## 14.2 `mdl_config_plugins` — Configuración de plugins

Similar a `mdl_config` pero organizada por plugin.

- `plugin`: Nombre del plugin ('auth_ldap', 'mod_assign', 'enrol_self', etc.).
- `name`: Nombre del parámetro.
- `value`: Valor.

Cada plugin almacena su propia configuración aquí. Para ver la versión de cada plugin instalado:
```sql
WHERE name = 'version'
```

---

# PARTE 15: INSIGNIAS (BADGES)

## 15.1 `mdl_badge` — Definición de insignias

- `type`: 1=sitio, 2=curso.
- `courseid`: ID del curso (si `type=2`).
- `status`: 0=inactiva, 1=activa, 2=activa bloqueada, 3=inactiva bloqueada.
- Tiene criterios de otorgamiento configurados en tablas asociadas (`mdl_badge_criteria`).

## 15.2 `mdl_badge_issued` — Insignias otorgadas

- `badgeid` → `mdl_badge.id`
- `userid` → `mdl_user.id`
- `dateissued`: Cuándo se otorgó.
- `uniquehash`: Hash único para verificación (se puede compartir como URL de verificación).

---

# PARTE 16: TAREAS PROGRAMADAS (CRON)

## 16.1 `mdl_task_scheduled` — Tareas programadas del cron

Moodle ejecuta tareas en segundo plano (recálculo de completitud, envío de emails, limpieza, etc.).

- `classname`: Clase PHP que ejecuta la tarea.
- `component`: Componente al que pertenece.
- `nextruntime`: Cuándo se ejecutará la próxima vez.
- `lastruntime`: Cuándo se ejecutó por última vez.
- `faildelay`: Si es > 0, la tarea ha fallado y está en espera.
- `disabled`: Si está deshabilitada.

---

# PARTE 17: RESUMEN DE RELACIONES CLAVE

## 17.1 Diagrama de relaciones principales

```
mdl_user
  ├──→ mdl_user_enrolments ──→ mdl_enrol ──→ mdl_course ──→ mdl_course_categories
  │         (matriculación)      (método)       (curso)          (categoría)
  │
  ├──→ mdl_role_assignments ──→ mdl_context ──→ (polimórfico según contextlevel)
  │         (rol asignado)        (ámbito)
  │
  ├──→ mdl_grade_grades ──→ mdl_grade_items ──→ mdl_grade_categories
  │      (notas)              (columnas)          (agrupación)
  │
  ├──→ mdl_course_modules_completion
  │      (completitud de actividades)
  │
  ├──→ mdl_assign_submission / mdl_quiz_attempts / mdl_forum_posts
  │      (trabajo del estudiante en cada actividad)
  │
  ├──→ mdl_groups_members ──→ mdl_groups ──→ mdl_course
  │      (pertenencia a grupos)
  │
  ├──→ mdl_logstore_standard_log
  │      (toda su actividad registrada)
  │
  └──→ mdl_messages / mdl_notifications
         (comunicación)
```

## 17.2 Cómo llegar de un dato a otro

| Quiero saber... | Camino de tablas |
|---|---|
| Qué cursos tiene un usuario | user → user_enrolments → enrol → course |
| Qué rol tiene en un curso | user → role_assignments → context(50) → course + role |
| Su nota final del curso | user → grade_grades → grade_items(itemtype='course') |
| Qué actividades completó | user → course_modules_completion → course_modules |
| Sus entregas de tareas | user → assign_submission → assign → course |
| Sus intentos de quiz | user → quiz_attempts → quiz → course |
| Sus posts en foros | user → forum_posts → forum_discussions → forum → course |
| Sus archivos subidos | user → files (userid) |
| Su actividad/logs | user → logstore_standard_log (userid) |
| En qué grupos está | user → groups_members → groups → course |
| Sus mensajes | user → messages (useridfrom) → message_conversations |
| Sus notificaciones | user → notifications (useridto) |

## 17.3 Tablas puente imprescindibles

| Tabla puente | Conecta | Con |
|---|---|---|
| `mdl_context` | Roles/permisos | Cursos, categorías, módulos, bloques, usuarios |
| `mdl_course_modules` | Cursos | Tablas específicas de actividad (quiz, assign, forum...) |
| `mdl_enrol` | Usuarios | Cursos (vía user_enrolments) |
| `mdl_grade_items` | Calificaciones | Cursos y actividades |

---

# PARTE 18: PREGUNTAS FRECUENTES

## ¿Por qué `mdl_context` es necesaria para casi todo?

Porque Moodle diseñó un sistema de permisos **genérico**: el mismo mecanismo de roles y capabilities funciona a nivel de sistema, categoría, curso, actividad y bloque. Para lograr eso, necesita una tabla que abstraiga todos esos "lugares" en un concepto unificado: el contexto.

## ¿Se puede hacer JOIN directo entre `mdl_role_assignments` y `mdl_course`?

**No.** No existe columna `courseid` en `role_assignments`. Siempre hay que pasar por `mdl_context`:
```
role_assignments.contextid → context.id (donde contextlevel=50) → context.instanceid = course.id
```

## ¿Cuál es la diferencia entre `rawgrade` y `finalgrade`?

- `rawgrade`: Lo que la actividad envió directamente (ej: 7 sobre 10).
- `finalgrade`: Lo que Moodle calculó después de aplicar pesos, escalas y agregación. Es la nota que ve el estudiante.

## ¿Por qué `mdl_course.id = 1` es especial?

Es la **Front Page** (página principal del sitio). No es un curso real. Por eso las queries llevan `WHERE c.id > 1`.

## ¿Qué pasó con `mdl_scorm_scoes_track`?

Desde Moodle 4.3, se dividió en tres tablas: `mdl_scorm_attempt`, `mdl_scorm_element` y `mdl_scorm_scoes_value` por razones de rendimiento y normalización.

## ¿Dónde está la columna `visible` de los bloques?

No está en `mdl_block_instances`. Está en `mdl_block_positions`. Un bloque sin registro en `block_positions` usa los valores por defecto de `block_instances`.

## ¿Qué significa `contextlevel = 50`?

Que el contexto se refiere a un **curso**. Y por tanto, `instanceid` apunta a `mdl_course.id`.

## ¿Cuándo aparecen registros con `contextid ≠ 1` en `mdl_role_capabilities`?

Solo cuando se hace un **override** (sobrescritura) de permisos en un contexto específico. La definición base de todos los permisos siempre tiene `contextid = 1` (sistema).
