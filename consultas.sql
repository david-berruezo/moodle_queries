USE moodle;

#################################################### USUARIOS #######################################################

# 1. USUARIOS Y AUTENTICACIÓN
# 1.1 Listar todos los usuarios activos (no eliminados ni suspendidos)
SELECT 
    u.id,
    u.username,
    u.firstname,
    u.lastname,
    u.email,
    u.auth,
    u.lang,
    u.city,
    u.country,
    u.firstaccess,
    FROM_UNIXTIME(u.firstaccess) AS primer_acceso,
    FROM_UNIXTIME(u.lastaccess) AS ultimo_acceso,
    FROM_UNIXTIME(u.timecreated) AS fecha_creacion
FROM mdl_user u
WHERE u.deleted = 0
  AND u.suspended = 0
  AND u.username <> 'guest'
ORDER BY u.lastname, u.firstname;


# 1.2 Usuarios que nunca han accedido a la plataforma
SELECT 
    u.id,
    u.username,
    u.firstname,
    u.lastname,
    u.email,
    u.timecreated,
    FROM_UNIXTIME(u.timecreated) AS fecha_creacion
FROM mdl_user u
WHERE u.deleted = 0
  AND u.firstaccess = 0
ORDER BY u.timecreated DESC;

# 1.3 Usuarios inactivos (sin acceso en los últimos 90 días)
SELECT 
    u.id,
    u.username,
    u.firstname,
    u.lastname,
    u.email,
    u.lastaccess,
    FROM_UNIXTIME(u.lastaccess) AS ultimo_acceso,
    DATEDIFF(NOW(), FROM_UNIXTIME(u.lastaccess)) AS dias_inactivo
FROM mdl_user u
WHERE u.deleted = 0
  AND u.suspended = 0
  AND u.lastaccess > 0
  AND u.lastaccess < UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 90 DAY))
ORDER BY u.lastaccess ASC;

# 1.4 Usuarios con sus campos de perfil personalizados
SELECT 
    u.id,
    u.username,
    u.firstname,
    u.lastname,
    uif.shortname AS campo,
    uif.name AS nombre_campo,
    uid.data AS valor
FROM mdl_user u
INNER JOIN mdl_user_info_data uid ON uid.userid = u.id
INNER JOIN mdl_user_info_field uif ON uif.id = uid.fieldid
WHERE u.deleted = 0
ORDER BY u.lastname, u.firstname, uif.sortorder;

# 1.5 Sesiones activas con datos de usuario
SELECT 
    s.id AS session_id,
    u.username,
    u.firstname,
    u.lastname,
    s.sid,
    FROM_UNIXTIME(s.timecreated) AS sesion_creada,
    FROM_UNIXTIME(s.timemodified) AS ultima_actividad,
    TIMESTAMPDIFF(MINUTE, FROM_UNIXTIME(s.timemodified), NOW()) AS minutos_inactivo
FROM mdl_sessions s
INNER JOIN mdl_user u ON u.id = s.userid
WHERE u.deleted = 0
ORDER BY s.timemodified DESC;

# 1.6 Conteo de usuarios por método de autenticación
SELECT 
    u.auth AS metodo_autenticacion,
    COUNT(*) AS total_usuarios
FROM mdl_user u
WHERE u.deleted = 0
  AND u.suspended = 0
GROUP BY u.auth
ORDER BY total_usuarios DESC;

# 1.7 Preferencias específicas de usuario (ej: idioma, editor)
SELECT 
    u.username,
    u.firstname,
    u.lastname,
    up.name AS preferencia,
    up.value AS valor
FROM mdl_user_preferences up
INNER JOIN mdl_user u ON u.id = up.userid
WHERE u.deleted = 0
  AND up.name IN ('auth_forcepasswordchange', 'email_bounce_count', 'htmleditor', 'lang')
ORDER BY u.lastname, up.name;


#################################################### CURSOS Y CATEGORÍAS #######################################################


# 2.1 Todos los cursos con su categoría padre
SELECT 
    c.id AS curso_id,
    c.fullname AS nombre_curso,
    c.shortname AS nombre_corto,
    c.idnumber AS id_externo,
    cc.name AS categoria,
    c.format AS formato,
    FROM_UNIXTIME(c.startdate) AS fecha_inicio,
    FROM_UNIXTIME(c.enddate) AS fecha_fin,
    c.visible,
    FROM_UNIXTIME(c.timecreated) AS fecha_creacion
FROM mdl_course c
INNER JOIN mdl_course_categories cc ON cc.id = c.category
WHERE c.id > 1  -- Excluir el curso del sitio (Frontpage)
ORDER BY cc.name, c.fullname;

# 2.2 Jerarquía completa de categorías (con categoría padre)
SELECT 
    cc.id,
    cc.name AS categoria,
    cc.idnumber,
    cc.depth AS nivel_profundidad,
    cc.path AS ruta,
    parent.name AS categoria_padre,
    cc.coursecount AS num_cursos,
    cc.visible
FROM mdl_course_categories cc
LEFT JOIN mdl_course_categories parent ON parent.id = cc.parent
ORDER BY cc.sortorder;

# 2.3 Secciones de un curso con sus actividades/recursos
SELECT 
    cs.section AS num_seccion,
    cs.name AS nombre_seccion,
    cm.id AS modulo_curso_id,
    m.name AS tipo_actividad,
    cm.instance AS instancia_id,
    cm.visible AS modulo_visible,
    cm.added AS fecha_agregado
FROM mdl_course_sections cs
INNER JOIN mdl_course_modules cm ON cm.section = cs.id AND cm.course = cs.course
INNER JOIN mdl_modules m ON m.id = cm.module
WHERE cs.course = 3
ORDER BY cs.section, cm.id;

# 2.4 Resumen de actividades por curso (cuántas de cada tipo)
SELECT 
    c.id AS curso_id,
    c.fullname AS nombre_curso,
    m.name AS tipo_actividad,
    COUNT(*) AS cantidad
FROM mdl_course c
INNER JOIN mdl_course_modules cm ON cm.course = c.id
INNER JOIN mdl_modules m ON m.id = cm.module
WHERE c.id > 1
AND cm.visible = 1
GROUP BY c.id, c.fullname, m.name
ORDER BY c.fullname, m.name;

# 2.5 Cursos sin actividades (cursos vacíos)
SELECT 
    c.id,
    c.fullname,
    c.shortname,
    cc.name AS categoria,
    FROM_UNIXTIME(c.timecreated) AS fecha_creacion
FROM mdl_course c
INNER JOIN mdl_course_categories cc ON cc.id = c.category
LEFT JOIN mdl_course_modules cm ON cm.course = c.id
WHERE c.id > 1
AND cm.id IS NULL
ORDER BY c.fullname;

# 2.6 Cursos ocultos o finalizados
SELECT 
    c.id,
    c.fullname,
    c.shortname,
    c.visible,
    FROM_UNIXTIME(c.enddate) AS fecha_fin,
    CASE 
        WHEN c.visible = 0 THEN 'Oculto'
        WHEN c.enddate > 0 AND c.enddate < UNIX_TIMESTAMP(NOW()) THEN 'Finalizado'
        ELSE 'Activo'
    END AS estado
FROM mdl_course c
WHERE c.id > 1
AND (c.visible = 0 OR (c.enddate > 0 AND c.enddate < UNIX_TIMESTAMP(NOW())))
ORDER BY c.fullname;


#################################################### MATRICULACIÓN #######################################################


# 3.1 Usuarios matriculados en un curso con su rol
SELECT 
    c.fullname AS curso,
    u.username,
    u.firstname,
    u.lastname,
    u.email,
    r.shortname AS rol,
    r.name AS nombre_rol,
    e.enrol AS metodo_matriculacion,
    FROM_UNIXTIME(ue.timecreated) AS fecha_matriculacion,
    CASE ue.status
        WHEN 0 THEN 'Activo'
        WHEN 1 THEN 'Suspendido'
    END AS estado
FROM mdl_user_enrolments ue
INNER JOIN mdl_enrol e ON e.id = ue.enrolid
INNER JOIN mdl_course c ON c.id = e.courseid
INNER JOIN mdl_user u ON u.id = ue.userid
INNER JOIN mdl_context ctx ON ctx.instanceid = c.id AND ctx.contextlevel = 50
INNER JOIN mdl_role_assignments ra ON ra.userid = u.id AND ra.contextid = ctx.id
INNER JOIN mdl_role r ON r.id = ra.roleid
WHERE u.deleted = 0
  AND c.id = 4
ORDER BY r.sortorder, u.lastname, u.firstname;

# 3.2 Conteo de estudiantes por curso
SELECT 
    c.id AS curso_id,
    c.fullname AS curso,
    c.shortname,
    COUNT(DISTINCT ue.userid) AS total_matriculados,
    SUM(CASE WHEN ue.status = 0 THEN 1 ELSE 0 END) AS activos,
    SUM(CASE WHEN ue.status = 1 THEN 1 ELSE 0 END) AS suspendidos
FROM mdl_course c
INNER JOIN mdl_enrol e ON e.courseid = c.id
INNER JOIN mdl_user_enrolments ue ON ue.enrolid = e.id
INNER JOIN mdl_user u ON u.id = ue.userid AND u.deleted = 0
WHERE c.id > 1
GROUP BY c.id, c.fullname, c.shortname
ORDER BY total_matriculados DESC;

# 3.3 Profesores de cada curso
SELECT 
    c.id AS curso_id,
    c.fullname AS curso,
    u.username,
    u.firstname,
    u.lastname,
    u.email,
    r.shortname AS rol
FROM mdl_course c
INNER JOIN mdl_context ctx ON ctx.instanceid = c.id AND ctx.contextlevel = 50
INNER JOIN mdl_role_assignments ra ON ra.contextid = ctx.id
INNER JOIN mdl_role r ON r.id = ra.roleid
INNER JOIN mdl_user u ON u.id = ra.userid
WHERE c.id > 1
  AND u.deleted = 0
  AND r.shortname IN ('editingteacher', 'teacher', 'manager')
ORDER BY c.fullname, r.shortname, u.lastname;

# 3.4 Usuarios matriculados en más de N cursos
SELECT 
    u.id,
    u.username,
    u.firstname,
    u.lastname,
    u.email,
    COUNT(DISTINCT e.courseid) AS total_cursos
FROM mdl_user u
INNER JOIN mdl_user_enrolments ue ON ue.userid = u.id
INNER JOIN mdl_enrol e ON e.id = ue.enrolid
WHERE u.deleted = 0
  AND ue.status = 0
GROUP BY u.id, u.username, u.firstname, u.lastname, u.email
HAVING total_cursos > 5
ORDER BY total_cursos DESC;

# 3.5 Métodos de matriculación por curso
SELECT 
    c.fullname AS curso,
    e.enrol AS metodo,
    e.status AS estado_metodo,
    r.shortname AS rol_por_defecto,
    COUNT(ue.id) AS usuarios_matriculados
FROM mdl_enrol e
INNER JOIN mdl_course c ON c.id = e.courseid
LEFT JOIN mdl_role r ON r.id = e.roleid
LEFT JOIN mdl_user_enrolments ue ON ue.enrolid = e.id
WHERE c.id > 1
GROUP BY c.fullname, e.enrol, e.status, r.shortname
ORDER BY c.fullname, e.enrol;

# 3.6 Usuarios NO matriculados en un curso específico (candidatos)
SELECT 
    u.id,
    u.username,
    u.firstname,
    u.lastname,
    u.email
FROM mdl_user u
WHERE u.deleted = 0
  AND u.suspended = 0
  AND u.id NOT IN (
      SELECT ue.userid
      FROM mdl_user_enrolments ue
      INNER JOIN mdl_enrol e ON e.id = ue.enrolid
      WHERE e.courseid = 4
  )
ORDER BY u.lastname, u.firstname;


######################################### CONTEXTOS, ROLES Y PERMISOS #########################################


# 4.1 Todos los roles con su arquetipo y cantidad de asignaciones
SELECT 
    r.id,
    r.shortname,
    r.name,
    r.archetype,
    COUNT(ra.id) AS total_asignaciones
FROM mdl_role r
LEFT JOIN mdl_role_assignments ra ON ra.roleid = r.id
GROUP BY r.id, r.shortname, r.name, r.archetype
ORDER BY r.sortorder;

# 4.2 Permisos (capabilities) de un rol específico
SELECT 
    r.shortname AS rol,
    rc.capability,
    CASE rc.permission
        WHEN 1 THEN 'ALLOW'
        WHEN -1 THEN 'PREVENT'
        WHEN -1000 THEN 'PROHIBIT'
        ELSE 'NOT SET'
    END AS permiso,
    CASE ctx.contextlevel
        WHEN 10 THEN 'Sistema'
        WHEN 40 THEN 'Categoría'
        WHEN 50 THEN 'Curso'
        WHEN 70 THEN 'Módulo'
        WHEN 80 THEN 'Bloque'
    END AS nivel_contexto
FROM mdl_role_capabilities rc
INNER JOIN mdl_role r ON r.id = rc.roleid
INNER JOIN mdl_context ctx ON ctx.id = rc.contextid
WHERE r.shortname = 'student'
ORDER BY rc.capability;

# 4.3 Contextos con sus tipos e instancias
SELECT 
    ctx.id,
    CASE ctx.contextlevel
        WHEN 10 THEN 'Sistema'
        WHEN 30 THEN 'Usuario'
        WHEN 40 THEN 'Categoría'
        WHEN 50 THEN 'Curso'
        WHEN 70 THEN 'Módulo'
        WHEN 80 THEN 'Bloque'
    END AS tipo_contexto,
    ctx.instanceid,
    ctx.path,
    ctx.depth
FROM mdl_context ctx
ORDER BY ctx.contextlevel, ctx.instanceid;

# 4.4 Asignaciones de rol a nivel de sistema (admins, managers)
SELECT 
    u.username,
    u.firstname,
    u.lastname,
    u.email,
    r.shortname AS rol,
    r.name AS nombre_rol,
    FROM_UNIXTIME(ra.timemodified) AS fecha_asignacion
FROM mdl_role_assignments ra
INNER JOIN mdl_role r ON r.id = ra.roleid
INNER JOIN mdl_user u ON u.id = ra.userid
INNER JOIN mdl_context ctx ON ctx.id = ra.contextid
WHERE ctx.contextlevel = 10  -- Nivel sistema
  AND u.deleted = 0
ORDER BY r.shortname, u.lastname;

# 4.5 Usuarios con múltiples roles en el mismo curso
SELECT 
    c.fullname AS curso,
    u.username,
    u.firstname,
    u.lastname,
    GROUP_CONCAT(DISTINCT r.shortname ORDER BY r.shortname SEPARATOR ', ') AS roles,
    COUNT(DISTINCT r.id) AS num_roles
FROM mdl_role_assignments ra
INNER JOIN mdl_context ctx ON ctx.id = ra.contextid AND ctx.contextlevel = 50
INNER JOIN mdl_course c ON c.id = ctx.instanceid
INNER JOIN mdl_user u ON u.id = ra.userid
INNER JOIN mdl_role r ON r.id = ra.roleid
WHERE u.deleted = 0
GROUP BY c.fullname, u.username, u.firstname, u.lastname
HAVING num_roles > 1
ORDER BY c.fullname, u.lastname;


############################################### CALIFICACIONES #####################################


# 5.1 Libro de calificaciones completo de un curso
SELECT 
    u.username,
    u.firstname,
    u.lastname,
    gi.itemname AS actividad,
    gi.itemtype,
    gi.itemmodule AS modulo,
    gi.grademax AS nota_maxima,
    gi.grademin AS nota_minima,
    gg.rawgrade AS nota_bruta,
    gg.finalgrade AS nota_final,
    FROM_UNIXTIME(gg.timemodified) AS fecha_calificacion
FROM mdl_grade_grades gg
INNER JOIN mdl_grade_items gi ON gi.id = gg.itemid
INNER JOIN mdl_user u ON u.id = gg.userid
WHERE gi.courseid = 4
  AND u.deleted = 0
ORDER BY u.lastname, u.firstname, gi.sortorder;


# 5.2 Media de calificaciones por actividad en un curso
SELECT 
    gi.id AS item_id,
    gi.itemname AS actividad,
    gi.itemmodule AS tipo,
    gi.grademax AS nota_maxima,
    ROUND(AVG(gg.finalgrade), 2) AS media,
    ROUND(MIN(gg.finalgrade), 2) AS nota_minima_obtenida,
    ROUND(MAX(gg.finalgrade), 2) AS nota_maxima_obtenida,
    COUNT(gg.id) AS total_calificados,
    ROUND(AVG(gg.finalgrade) / gi.grademax * 100, 1) AS porcentaje_medio
FROM mdl_grade_items gi
INNER JOIN mdl_grade_grades gg ON gg.itemid = gi.id AND gg.finalgrade IS NOT NULL
WHERE gi.courseid = 4
GROUP BY gi.id, gi.itemname, gi.itemmodule, gi.grademax
ORDER BY gi.sortorder;

# 5.3 Nota final del curso por estudiante (item type = 'course')
SELECT 
    c.fullname AS curso,
    u.username,
    u.firstname,
    u.lastname,
    ROUND(gg.finalgrade, 2) AS nota_final_curso,
    ROUND(gi.grademax, 2) AS nota_maxima,
    ROUND(gg.finalgrade / gi.grademax * 100, 1) AS porcentaje,
    CASE 
        WHEN gg.finalgrade >= (gi.grademax * 0.5) THEN 'APROBADO'
        ELSE 'SUSPENDIDO'
    END AS resultado
FROM mdl_grade_grades gg
INNER JOIN mdl_grade_items gi ON gi.id = gg.itemid
INNER JOIN mdl_course c ON c.id = gi.courseid
INNER JOIN mdl_user u ON u.id = gg.userid
WHERE gi.itemtype = 'course'
  AND gg.finalgrade IS NOT NULL
  AND u.deleted = 0
  AND gi.courseid = 4
ORDER BY gg.finalgrade DESC;

# 5.4 Categorías de calificación con sus ítems
SELECT 
    gc.id AS categoria_id,
    gc.fullname AS categoria_calificacion,
    gc.aggregation,
    CASE gc.aggregation
        WHEN 0 THEN 'Media de calificaciones'
        WHEN 10 THEN 'Media ponderada'
        WHEN 11 THEN 'Media ponderada simple'
        WHEN 12 THEN 'Media de cal. con créditos extra'
        WHEN 13 THEN 'Mediana'
        WHEN 2 THEN 'Calificación más baja'
        WHEN 4 THEN 'Calificación más alta'
        WHEN 6 THEN 'Suma de calificaciones'
    END AS tipo_agregacion,
    gi.itemname AS item,
    gi.itemmodule AS modulo,
    gi.grademax
FROM mdl_grade_categories gc
LEFT JOIN mdl_grade_items gi ON gi.categoryid = gc.id AND gi.itemtype = 'mod'
WHERE gc.courseid = 4
ORDER BY gc.fullname, gi.sortorder;


# 5.5 Escalas de calificación disponibles
SELECT 
    s.id,
    s.name AS nombre_escala,
    s.scale AS valores,
    COALESCE(c.fullname, 'Global (sitio)') AS curso,
    s.description
FROM mdl_scale s
LEFT JOIN mdl_course c ON c.id = s.courseid
ORDER BY s.name;


# 5.6 Estudiantes sin calificar en actividades obligatorias
SELECT 
    c.fullname AS curso,
    gi.itemname AS actividad,
    u.username,
    u.firstname,
    u.lastname
FROM mdl_grade_items gi
INNER JOIN mdl_course c ON c.id = gi.courseid
CROSS JOIN mdl_user u
INNER JOIN mdl_user_enrolments ue ON ue.userid = u.id
INNER JOIN mdl_enrol e ON e.id = ue.enrolid AND e.courseid = gi.courseid
INNER JOIN mdl_context ctx ON ctx.instanceid = c.id AND ctx.contextlevel = 50
INNER JOIN mdl_role_assignments ra ON ra.userid = u.id AND ra.contextid = ctx.id
INNER JOIN mdl_role r ON r.id = ra.roleid AND r.shortname = 'student'
LEFT JOIN mdl_grade_grades gg ON gg.itemid = gi.id AND gg.userid = u.id
WHERE gi.courseid = 4
  AND gi.itemtype = 'mod'
  AND u.deleted = 0
  AND gg.finalgrade IS NULL
ORDER BY gi.itemname, u.lastname;


############################################# COMPLETITUD DE ACTIVIDADES Y CURSOS #############################


# 6.1 Estado de completitud de actividades por usuario en un curso
SELECT 
    u.username,
    u.firstname,
    u.lastname,
    m.name AS tipo_actividad,
    cm.id AS modulo_id,
    CASE cmc.completionstate
        WHEN 0 THEN 'No completado'
        WHEN 1 THEN 'Completado'
        WHEN 2 THEN 'Completado - Aprobado'
        WHEN 3 THEN 'Completado - Suspendido'
        ELSE 'Sin seguimiento'
    END AS estado_completitud,
    FROM_UNIXTIME(cmc.timemodified) AS fecha_completado
FROM mdl_course_modules cm
INNER JOIN mdl_modules m ON m.id = cm.module
INNER JOIN mdl_context ctx ON ctx.instanceid = cm.course AND ctx.contextlevel = 50
INNER JOIN mdl_role_assignments ra ON ra.contextid = ctx.id
INNER JOIN mdl_role r ON r.id = ra.roleid AND r.shortname = 'student'
INNER JOIN mdl_user u ON u.id = ra.userid AND u.deleted = 0
LEFT JOIN mdl_course_modules_completion cmc ON cmc.coursemoduleid = cm.id AND cmc.userid = u.id
WHERE cm.course = 4
  AND cm.completion > 0  -- Solo actividades con seguimiento habilitado
ORDER BY u.lastname, u.firstname, cm.id;

# 6.2 Porcentaje de completitud por estudiante en un curso
SELECT 
    u.username,
    u.firstname,
    u.lastname,
    COUNT(cm.id) AS total_actividades_rastreadas,
    SUM(CASE WHEN cmc.completionstate IN (1, 2) THEN 1 ELSE 0 END) AS completadas,
    ROUND(
        SUM(CASE WHEN cmc.completionstate IN (1, 2) THEN 1 ELSE 0 END) / COUNT(cm.id) * 100, 1
    ) AS porcentaje_completitud
FROM mdl_course_modules cm
INNER JOIN mdl_context ctx ON ctx.instanceid = cm.course AND ctx.contextlevel = 50
INNER JOIN mdl_role_assignments ra ON ra.contextid = ctx.id
INNER JOIN mdl_role r ON r.id = ra.roleid AND r.shortname = 'student'
INNER JOIN mdl_user u ON u.id = ra.userid AND u.deleted = 0
LEFT JOIN mdl_course_modules_completion cmc ON cmc.coursemoduleid = cm.id AND cmc.userid = u.id
WHERE cm.course = 4
  AND cm.completion > 0
GROUP BY u.id, u.username, u.firstname, u.lastname
ORDER BY porcentaje_completitud DESC;

# 6.3 Completitud del curso (mdl_course_completions)
SELECT 
    c.fullname AS curso,
    u.username,
    u.firstname,
    u.lastname,
    FROM_UNIXTIME(cc.timecompleted) AS fecha_completado,
    cc.reaggregate
FROM mdl_course_completions cc
INNER JOIN mdl_course c ON c.id = cc.course
INNER JOIN mdl_user u ON u.id = cc.userid
WHERE u.deleted = 0
  AND cc.timecompleted IS NOT NULL
  AND c.id = 4
ORDER BY cc.timecompleted DESC;


################################################## TAREAS (ASSIGN) ############################################################


# 7.1 Todas las tareas de un curso con fechas importantes

SELECT 
    a.id,
    a.name AS tarea,
    c.fullname AS curso,
    FROM_UNIXTIME(a.allowsubmissionsfromdate) AS abierta_desde,
    FROM_UNIXTIME(a.duedate) AS fecha_limite,
    FROM_UNIXTIME(a.cutoffdate) AS fecha_corte,
    a.grade AS nota_maxima,
    a.teamsubmission AS entrega_grupal,
    a.requiresubmissionstatement AS declaracion_requerida
FROM mdl_assign a
INNER JOIN mdl_course c ON c.id = a.course
WHERE a.course = 4
ORDER BY a.duedate;

# 7.2 Entregas de tareas con estado y nota
SELECT 
    a.name AS tarea,
    u.username,
    u.firstname,
    u.lastname,
    asub.status AS estado_entrega,
    FROM_UNIXTIME(asub.timemodified) AS fecha_entrega,
    ag.grade AS nota,
    a.grade AS nota_maxima,
    ROUND(ag.grade / a.grade * 100, 1) AS porcentaje,
    FROM_UNIXTIME(ag.timemodified) AS fecha_calificacion,
    grader.firstname AS calificado_por_nombre,
    grader.lastname AS calificado_por_apellido
FROM mdl_assign a
INNER JOIN mdl_assign_submission asub ON asub.assignment = a.id
INNER JOIN mdl_user u ON u.id = asub.userid
LEFT JOIN mdl_assign_grades ag ON ag.assignment = a.id AND ag.userid = u.id
LEFT JOIN mdl_user grader ON grader.id = ag.grader
WHERE a.course = 4
  AND asub.latest = 1
  AND u.deleted = 0
ORDER BY a.name, u.lastname, u.firstname;


# 7.3 Tareas entregadas fuera de plazo
SELECT 
    a.name AS tarea,
    u.username,
    u.firstname,
    u.lastname,
    FROM_UNIXTIME(a.duedate) AS fecha_limite,
    FROM_UNIXTIME(asub.timemodified) AS fecha_entrega,
    ROUND((asub.timemodified - a.duedate) / 3600, 1) AS horas_retraso
FROM mdl_assign a
INNER JOIN mdl_assign_submission asub ON asub.assignment = a.id
INNER JOIN mdl_user u ON u.id = asub.userid
WHERE a.course = 4
  AND asub.latest = 1
  AND asub.status = 'submitted'
  AND a.duedate > 0
  AND asub.timemodified > a.duedate
  AND u.deleted = 0
ORDER BY horas_retraso DESC;


# 7.4 Tareas pendientes de calificar
SELECT 
    a.name AS tarea,
    c.fullname AS curso,
    u.username,
    u.firstname,
    u.lastname,
    asub.status AS estado_entrega,
    FROM_UNIXTIME(asub.timemodified) AS fecha_entrega
FROM mdl_assign a
INNER JOIN mdl_course c ON c.id = a.course
INNER JOIN mdl_assign_submission asub ON asub.assignment = a.id
INNER JOIN mdl_user u ON u.id = asub.userid
LEFT JOIN mdl_assign_grades ag ON ag.assignment = a.id AND ag.userid = u.id
WHERE asub.latest = 1
  AND asub.status = 'submitted'
  AND (ag.grade IS NULL OR ag.grade = -1)
  AND u.deleted = 0
ORDER BY c.fullname, a.name, asub.timemodified;

# 7.5 Estudiantes que NO han entregado una tarea
SELECT 
    a.name AS tarea,
    u.username,
    u.firstname,
    u.lastname,
    u.email
FROM mdl_assign a
INNER JOIN mdl_context ctx ON ctx.instanceid = a.course AND ctx.contextlevel = 50
INNER JOIN mdl_role_assignments ra ON ra.contextid = ctx.id
INNER JOIN mdl_role r ON r.id = ra.roleid AND r.shortname = 'student'
INNER JOIN mdl_user u ON u.id = ra.userid AND u.deleted = 0
LEFT JOIN mdl_assign_submission asub ON asub.assignment = a.id 
    AND asub.userid = u.id AND asub.latest = 1 AND asub.status = 'submitted'
WHERE a.course = 4
  AND asub.id IS NULL
ORDER BY a.name, u.lastname;


############################################## CUESTIONARIOS (QUIZ) #############################################


# 8.1 Cuestionarios de un curso con configuración
SELECT 
    q.id,
    q.name AS cuestionario,
    c.fullname AS curso,
    q.attempts AS intentos_permitidos,
    FROM_UNIXTIME(q.timeopen) AS fecha_apertura,
    FROM_UNIXTIME(q.timeclose) AS fecha_cierre,
    q.timelimit AS tiempo_limite_seg,
    q.grade AS nota_maxima,
    q.sumgrades AS suma_puntos_preguntas,
    CASE q.grademethod
        WHEN 1 THEN 'Calificación más alta'
        WHEN 2 THEN 'Calificación media'
        WHEN 3 THEN 'Primer intento'
        WHEN 4 THEN 'Último intento'
    END AS metodo_calificacion
FROM mdl_quiz q
INNER JOIN mdl_course c ON c.id = q.course
WHERE q.course = 4
ORDER BY q.timeopen;

# 8.2 Intentos de cuestionario con calificaciones
SELECT 
    q.name AS cuestionario,
    u.username,
    u.firstname,
    u.lastname,
    qa.attempt AS num_intento,
    qa.state AS estado,
    ROUND(qa.sumgrades, 2) AS puntos_obtenidos,
    ROUND(q.sumgrades, 2) AS puntos_totales,
    ROUND(qa.sumgrades / q.sumgrades * q.grade, 2) AS nota_sobre_max,
    q.grade AS nota_maxima,
    FROM_UNIXTIME(qa.timestart) AS inicio,
    FROM_UNIXTIME(qa.timefinish) AS fin,
    ROUND((qa.timefinish - qa.timestart) / 60, 1) AS duracion_minutos
FROM mdl_quiz_attempts qa
INNER JOIN mdl_quiz q ON q.id = qa.quiz
INNER JOIN mdl_user u ON u.id = qa.userid
WHERE q.course = 4
  AND u.deleted = 0
ORDER BY q.name, u.lastname, qa.attempt;

# 8.3 Mejor calificación por estudiante en cada cuestionario
SELECT 
    q.name AS cuestionario,
    u.username,
    u.firstname,
    u.lastname,
    COUNT(qa.id) AS total_intentos,
    ROUND(MAX(qa.sumgrades / q.sumgrades * q.grade), 2) AS mejor_nota,
    q.grade AS nota_maxima,
    ROUND(MAX(qa.sumgrades / q.sumgrades * 100), 1) AS mejor_porcentaje
FROM mdl_quiz_attempts qa
INNER JOIN mdl_quiz q ON q.id = qa.quiz
INNER JOIN mdl_user u ON u.id = qa.userid
WHERE q.course = 4
  AND qa.state = 'finished'
  AND u.deleted = 0
GROUP BY q.name, u.id, u.username, u.firstname, u.lastname, q.grade
ORDER BY q.name, mejor_nota DESC;


# 8.4 Preguntas del banco con sus respuestas
SELECT 
    q.id AS pregunta_id,
    q.name AS nombre_pregunta,
    q.qtype AS tipo_pregunta,
    q.questiontext AS texto_pregunta,
    qa.answer AS respuesta,
    qa.fraction AS fraccion_correcta,
    qa.feedback
FROM mdl_question q
LEFT JOIN mdl_question_answers qa ON qa.question = q.id
ORDER BY q.id, qa.id;


# 8.5 Estadísticas de cuestionarios (aprobados/suspendidos)
SELECT 
    q.name AS cuestionario,
    COUNT(DISTINCT qa.userid) AS total_estudiantes,
    ROUND(AVG(qa.sumgrades / q.sumgrades * q.grade), 2) AS nota_media,
    ROUND(MIN(qa.sumgrades / q.sumgrades * q.grade), 2) AS nota_minima,
    ROUND(MAX(qa.sumgrades / q.sumgrades * q.grade), 2) AS nota_maxima,
    SUM(CASE WHEN (qa.sumgrades / q.sumgrades * 100) >= 50 THEN 1 ELSE 0 END) AS aprobados,
    SUM(CASE WHEN (qa.sumgrades / q.sumgrades * 100) < 50 THEN 1 ELSE 0 END) AS suspendidos,
    ROUND(
        SUM(CASE WHEN (qa.sumgrades / q.sumgrades * 100) >= 50 THEN 1 ELSE 0 END) /
        COUNT(*) * 100, 1
    ) AS tasa_aprobados_pct
FROM mdl_quiz q
INNER JOIN mdl_quiz_attempts qa ON qa.quiz = q.id AND qa.state = 'finished'
WHERE q.course = 4
GROUP BY q.id, q.name
ORDER BY q.name;


#################################################### FOROS #########################################


# 9.1 Foros de un curso con estadísticas
SELECT 
    f.id,
    f.name AS foro,
    f.type AS tipo_foro,
    c.fullname AS curso,
    COUNT(DISTINCT fd.id) AS total_discusiones,
    COUNT(DISTINCT fp.id) AS total_posts,
    COUNT(DISTINCT fp.userid) AS usuarios_participantes
FROM mdl_forum f
INNER JOIN mdl_course c ON c.id = f.course
LEFT JOIN mdl_forum_discussions fd ON fd.forum = f.id
LEFT JOIN mdl_forum_posts fp ON fp.discussion = fd.id
WHERE f.course = 4
GROUP BY f.id, f.name, f.type, c.fullname
ORDER BY f.name;


# 9.2 Discusiones con primer y último post
SELECT 
    f.name AS foro,
    fd.name AS discusion,
    creator.firstname AS creador_nombre,
    creator.lastname AS creador_apellido,
    FROM_UNIXTIME(fd.timemodified) AS ultima_actividad,
    COUNT(fp.id) AS total_respuestas,
    MAX(FROM_UNIXTIME(fp.created)) AS ultimo_post
FROM mdl_forum_discussions fd
INNER JOIN mdl_forum f ON f.id = fd.forum
INNER JOIN mdl_user creator ON creator.id = fd.userid
LEFT JOIN mdl_forum_posts fp ON fp.discussion = fd.id
WHERE f.course = 4
GROUP BY f.name, fd.id, fd.name, creator.firstname, creator.lastname, fd.timemodified
ORDER BY fd.timemodified DESC;

# 9.3 Todos los posts de un foro (hilo completo con jerarquía)
SELECT 
    fd.name AS discusion,
    fp.id AS post_id,
    fp.parent AS padre_id,
    u.username,
    u.firstname,
    u.lastname,
    fp.subject AS asunto,
    fp.message AS mensaje,
    FROM_UNIXTIME(fp.created) AS fecha_creacion,
    FROM_UNIXTIME(fp.modified) AS fecha_modificacion
FROM mdl_forum_posts fp
INNER JOIN mdl_forum_discussions fd ON fd.id = fp.discussion
INNER JOIN mdl_forum f ON f.id = fd.forum
INNER JOIN mdl_user u ON u.id = fp.userid
WHERE f.course = 4
ORDER BY fd.name, fp.created;

# 9.4 Participación en foros por estudiante
SELECT 
    u.username,
    u.firstname,
    u.lastname,
    COUNT(DISTINCT fd.id) AS discusiones_creadas,
    COUNT(DISTINCT fp.id) AS total_posts,
    SUM(CASE WHEN fp.parent = 0 THEN 1 ELSE 0 END) AS posts_iniciales,
    SUM(CASE WHEN fp.parent > 0 THEN 1 ELSE 0 END) AS respuestas,
    MAX(FROM_UNIXTIME(fp.created)) AS ultimo_post
FROM mdl_user u
INNER JOIN mdl_forum_posts fp ON fp.userid = u.id
INNER JOIN mdl_forum_discussions fd ON fd.id = fp.discussion
INNER JOIN mdl_forum f ON f.id = fd.forum
WHERE f.course = 4
  AND u.deleted = 0
GROUP BY u.id, u.username, u.firstname, u.lastname
ORDER BY total_posts DESC;


################################################# SCORM ###########################################


# 10.1 Paquetes SCORM con seguimiento
SELECT 
    s.name AS paquete_scorm,
    c.fullname AS curso,
    u.username,
    u.firstname,
    u.lastname,
    sa.attempt AS num_intento,
    se.element,
    sv.value,
    FROM_UNIXTIME(sv.timemodified) AS fecha
FROM mdl_scorm s
INNER JOIN mdl_course c ON c.id = s.course
INNER JOIN mdl_scorm_attempt sa ON sa.scormid = s.id
INNER JOIN mdl_user u ON u.id = sa.userid
INNER JOIN mdl_scorm_scoes_value sv ON sv.attemptid = sa.id
INNER JOIN mdl_scorm_element se ON se.id = sv.elementid
INNER JOIN mdl_scorm_scoes sc ON sc.id = sv.scoid
WHERE s.course = 4
  AND se.element IN (
      'cmi.core.lesson_status', 
      'cmi.core.score.raw', 
      'cmi.core.total_time',
      'cmi.completion_status',
      'cmi.success_status',
      'cmi.score.raw'
  )
ORDER BY s.name, u.lastname, se.element;

# 10.2 Resumen de progreso SCORM por usuario (nueva estructura)
SELECT 
    s.name AS paquete,
    u.username,
    u.firstname,
    u.lastname,
    sa.attempt AS num_intento,
    MAX(CASE WHEN se.element IN ('cmi.core.lesson_status', 'cmi.completion_status') 
        THEN sv.value END) AS estado,
    MAX(CASE WHEN se.element IN ('cmi.core.score.raw', 'cmi.score.raw') 
        THEN sv.value END) AS puntuacion,
    MAX(CASE WHEN se.element = 'cmi.core.total_time' 
        THEN sv.value END) AS tiempo_total,
    MAX(CASE WHEN se.element = 'cmi.success_status' 
        THEN sv.value END) AS exito
FROM mdl_scorm s
INNER JOIN mdl_scorm_attempt sa ON sa.scormid = s.id
INNER JOIN mdl_user u ON u.id = sa.userid
INNER JOIN mdl_scorm_scoes_value sv ON sv.attemptid = sa.id
INNER JOIN mdl_scorm_element se ON se.id = sv.elementid
WHERE s.course = 4
  AND u.deleted = 0
GROUP BY s.name, u.id, u.username, u.firstname, u.lastname, sa.attempt
ORDER BY s.name, u.lastname, sa.attempt;

# 10.3 Elementos SCORM disponibles (útil para explorar qué datos hay)
SELECT 
    se.element,
    COUNT(*) AS total_registros
FROM mdl_scorm_element se
INNER JOIN mdl_scorm_scoes_value sv ON sv.elementid = se.id
GROUP BY se.element
ORDER BY total_registros DESC;


########################################### GRUPOS Y COHORTES #######################################


# 11.1 Grupos de un curso con sus miembros
SELECT 
    g.name AS grupo,
    g.description AS descripcion_grupo,
    u.username,
    u.firstname,
    u.lastname,
    u.email,
    FROM_UNIXTIME(gm.timeadded) AS fecha_agregado
FROM mdl_groups g
INNER JOIN mdl_groups_members gm ON gm.groupid = g.id
INNER JOIN mdl_user u ON u.id = gm.userid
WHERE g.courseid = 4
  AND u.deleted = 0
ORDER BY g.name, u.lastname;


# 11.2 Agrupamientos (groupings) con sus grupos
SELECT 
    gr.name AS agrupamiento,
    g.name AS grupo,
    COUNT(gm.id) AS total_miembros
FROM mdl_groupings gr
INNER JOIN mdl_groupings_groups gg ON gg.groupingid = gr.id
INNER JOIN mdl_groups g ON g.id = gg.groupid
LEFT JOIN mdl_groups_members gm ON gm.groupid = g.id
WHERE gr.courseid = 4
GROUP BY gr.name, g.name
ORDER BY gr.name, g.name;

# 11.3 Cohortes del sitio con miembros
SELECT 
    co.name AS cohorte,
    co.idnumber AS id_externo,
    co.description,
    CASE ctx.contextlevel
        WHEN 10 THEN 'Sistema'
        WHEN 40 THEN 'Categoría'
    END AS nivel,
    COUNT(cm.id) AS total_miembros
FROM mdl_cohort co
INNER JOIN mdl_context ctx ON ctx.id = co.contextid
LEFT JOIN mdl_cohort_members cm ON cm.cohortid = co.id
GROUP BY co.id, co.name, co.idnumber, co.description, ctx.contextlevel
ORDER BY co.name;

# 11.4 Miembros de una cohorte específica
SELECT 
    co.name AS cohorte,
    u.username,
    u.firstname,
    u.lastname,
    u.email,
    FROM_UNIXTIME(cm.timeadded) AS fecha_agregado
FROM mdl_cohort_members cm
INNER JOIN mdl_cohort co ON co.id = cm.cohortid
INNER JOIN mdl_user u ON u.id = cm.userid
WHERE co.id = 4
  AND u.deleted = 0
ORDER BY u.lastname, u.firstname;

# 11.5 Usuarios sin grupo en un curso
SELECT 
    u.username,
    u.firstname,
    u.lastname
FROM mdl_user u
INNER JOIN mdl_user_enrolments ue ON ue.userid = u.id
INNER JOIN mdl_enrol e ON e.id = ue.enrolid
LEFT JOIN mdl_groups_members gm ON gm.userid = u.id
LEFT JOIN mdl_groups g ON g.id = gm.groupid AND g.courseid = e.courseid
WHERE e.courseid = 4
  AND u.deleted = 0
  AND ue.status = 0
  AND g.id IS NULL
ORDER BY u.lastname;


############################################################ ARCHIVOS ########################################################


# 12.1 Archivos subidos por usuarios (sin archivos de sistema)
SELECT 
    f.id,
    f.filename,
    f.component,
    f.filearea,
    f.filepath,
    ROUND(f.filesize / 1024, 2) AS tamano_kb,
    ROUND(f.filesize / 1048576, 2) AS tamano_mb,
    f.mimetype,
    u.username AS subido_por,
    FROM_UNIXTIME(f.timecreated) AS fecha_subida,
    f.contenthash
FROM mdl_files f
LEFT JOIN mdl_user u ON u.id = f.userid
WHERE f.filename <> '.'
  AND f.filesize > 0
ORDER BY f.timecreated DESC
LIMIT 100;

# 12.2 Espacio usado por componente
SELECT 
    f.component,
    f.filearea,
    COUNT(*) AS total_archivos,
    ROUND(SUM(f.filesize) / 1048576, 2) AS total_mb,
    ROUND(AVG(f.filesize) / 1024, 2) AS media_kb
FROM mdl_files f
WHERE f.filename <> '.'
  AND f.filesize > 0
GROUP BY f.component, f.filearea
ORDER BY total_mb DESC;

# 12.3 Archivos más grandes del sitio
SELECT 
    f.filename,
    f.component,
    f.filearea,
    ROUND(f.filesize / 1048576, 2) AS tamano_mb,
    f.mimetype,
    u.username AS subido_por,
    FROM_UNIXTIME(f.timecreated) AS fecha
FROM mdl_files f
LEFT JOIN mdl_user u ON u.id = f.userid
WHERE f.filename <> '.'
  AND f.filesize > 0
ORDER BY f.filesize DESC
LIMIT 50;

# 12.4 Espacio usado por curso
SELECT 
    c.fullname AS curso,
    COUNT(DISTINCT f.contenthash) AS archivos_unicos,
    COUNT(f.id) AS total_referencias,
    ROUND(SUM(f.filesize) / 1048576, 2) AS total_mb
FROM mdl_files f
INNER JOIN mdl_context ctx ON ctx.id = f.contextid
INNER JOIN mdl_course c ON (
    (ctx.contextlevel = 50 AND ctx.instanceid = c.id)
    OR (ctx.contextlevel = 70 AND ctx.instanceid IN (
        SELECT cm.id FROM mdl_course_modules cm WHERE cm.course = c.id
    ))
)
WHERE f.filename <> '.'
  AND f.filesize > 0
GROUP BY c.id, c.fullname
ORDER BY total_mb DESC;


############################################################# LOGS Y EVENTOS ###############################################


# 13.1 Últimos eventos del sitio
SELECT 
    l.id,
    l.eventname,
    l.component,
    l.action,
    l.target,
    u.username,
    c.fullname AS curso,
    FROM_UNIXTIME(l.timecreated) AS fecha,
    l.ip AS direccion_ip
FROM mdl_logstore_standard_log l
LEFT JOIN mdl_user u ON u.id = l.userid
LEFT JOIN mdl_course c ON c.id = l.courseid
ORDER BY l.timecreated DESC
LIMIT 100;


# 13.2 Actividad por usuario en un curso (resumen)
SELECT 
    u.username,
    u.firstname,
    u.lastname,
    COUNT(l.id) AS total_eventos,
    COUNT(DISTINCT DATE(FROM_UNIXTIME(l.timecreated))) AS dias_activos,
    MIN(FROM_UNIXTIME(l.timecreated)) AS primer_evento,
    MAX(FROM_UNIXTIME(l.timecreated)) AS ultimo_evento
FROM mdl_logstore_standard_log l
INNER JOIN mdl_user u ON u.id = l.userid
WHERE l.courseid = 4
  AND u.deleted = 0
GROUP BY u.id, u.username, u.firstname, u.lastname
ORDER BY total_eventos DESC;

# 13.3 Acciones más frecuentes por curso
SELECT 
    l.component,
    l.action,
    l.target,
    l.eventname,
    COUNT(*) AS total_ocurrencias
FROM mdl_logstore_standard_log l
WHERE l.courseid = 4
GROUP BY l.component, l.action, l.target, l.eventname
ORDER BY total_ocurrencias DESC
LIMIT 30;

# 13.4 Logins por día (últimos 30 días)
SELECT 
    DATE(FROM_UNIXTIME(l.timecreated)) AS fecha,
    COUNT(DISTINCT l.userid) AS usuarios_unicos,
    COUNT(*) AS total_logins
FROM mdl_logstore_standard_log l
WHERE l.eventname = '\\core\\event\\user_loggedin'
  AND l.timecreated >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))
GROUP BY DATE(FROM_UNIXTIME(l.timecreated))
ORDER BY fecha DESC;

# 13.5 Usuarios más activos del sitio (últimos 30 días)
SELECT 
    u.username,
    u.firstname,
    u.lastname,
    COUNT(l.id) AS total_acciones,
    COUNT(DISTINCT l.courseid) AS cursos_accedidos,
    COUNT(DISTINCT DATE(FROM_UNIXTIME(l.timecreated))) AS dias_activos
FROM mdl_logstore_standard_log l
INNER JOIN mdl_user u ON u.id = l.userid
WHERE l.timecreated >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))
  AND u.deleted = 0
GROUP BY u.id, u.username, u.firstname, u.lastname
ORDER BY total_acciones DESC
LIMIT 20;

# 13.6 Recursos/actividades más vistos en un curso
SELECT 
    l.objecttable AS tabla_objeto,
    l.objectid,
    l.target,
    COUNT(*) AS total_vistas,
    COUNT(DISTINCT l.userid) AS usuarios_unicos
FROM mdl_logstore_standard_log l
WHERE l.courseid = 45
  AND l.action = 'viewed'
  AND l.target IN ('course_module', 'course')
GROUP BY l.objecttable, l.objectid, l.target
ORDER BY total_vistas DESC
LIMIT 20;

# 13.7 Auditoría: acciones de administradores
SELECT 
    u.username,
    u.firstname,
    u.lastname,
    l.eventname,
    l.action,
    l.target,
    l.other,
    FROM_UNIXTIME(l.timecreated) AS fecha,
    l.ip
FROM mdl_logstore_standard_log l
INNER JOIN mdl_user u ON u.id = l.userid
INNER JOIN mdl_context ctx ON ctx.id = l.contextid AND ctx.contextlevel = 10
INNER JOIN mdl_role_assignments ra ON ra.userid = u.id AND ra.contextid = ctx.id
INNER JOIN mdl_role r ON r.id = ra.roleid AND r.shortname = 'manager'
WHERE l.timecreated >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 7 DAY))
ORDER BY l.timecreated DESC;


############################################# CONFIGURACIÓN DEL SITIO ###########################################


# 14.1 Configuración global de Moodle
SELECT 
    name AS parametro,
    value AS valor
FROM mdl_config
WHERE name IN (
    'fullname', 'shortname', 'summary', 'lang',
    'timezone', 'country', 'defaultcity',
    'enablecompletion', 'enableavailability',
    'enablebadges', 'enableanalytics',
    'registerauth', 'guestloginbutton',
    'maxbytes', 'userquota',
    'smtphosts', 'noreplyaddress',
    'version', 'release'
)
ORDER BY NAME;

# 14.2 Configuración de plugins
SELECT 
    plugin,
    name AS parametro,
    value AS valor
FROM mdl_config_plugins
WHERE plugin IN ('auth_ldap', 'auth_oauth2', 'enrol_self', 'enrol_manual', 'mod_assign', 'mod_quiz')
ORDER BY plugin, NAME;


# 14.3 Plugins instalados y sus versiones
SELECT 
    plugin,
    name,
    value AS version
FROM mdl_config_plugins
WHERE name = 'version'
ORDER BY PLUGIN;

# 14.4 Módulos de actividad habilitados
SELECT 
    m.id,
    m.name AS modulo,
    m.visible AS habilitado,
    (SELECT COUNT(*) FROM mdl_course_modules cm WHERE cm.module = m.id) AS instancias_totales
FROM mdl_modules m
ORDER BY m.name;


############################################# INSIGNIAS (BADGES) ####################################

# 15.1 Insignias del sitio/curso con criterios
SELECT 
    b.id,
    b.name AS insignia,
    b.description,
    CASE b.type
        WHEN 1 THEN 'Sitio'
        WHEN 2 THEN 'Curso'
    END AS tipo,
    COALESCE(c.fullname, 'Global') AS curso,
    CASE b.status
        WHEN 0 THEN 'Inactiva'
        WHEN 1 THEN 'Activa'
        WHEN 2 THEN 'Activa (bloqueada)'
        WHEN 3 THEN 'Inactiva (bloqueada)'
    END AS estado,
    FROM_UNIXTIME(b.timecreated) AS creada,
    (SELECT COUNT(*) FROM mdl_badge_issued bi WHERE bi.badgeid = b.id) AS veces_otorgada
FROM mdl_badge b
LEFT JOIN mdl_course c ON c.id = b.courseid
ORDER BY b.name;

# 15.2 Insignias otorgadas a usuarios
SELECT 
    b.name AS insignia,
    u.username,
    u.firstname,
    u.lastname,
    FROM_UNIXTIME(bi.dateissued) AS fecha_otorgada,
    bi.uniquehash
FROM mdl_badge_issued bi
INNER JOIN mdl_badge b ON b.id = bi.badgeid
INNER JOIN mdl_user u ON u.id = bi.userid
WHERE u.deleted = 0
ORDER BY bi.dateissued DESC;


################################################################ MENSAJERÍA ######################################################


# 16.1 Mensajes recientes entre usuarios
SELECT 
    m.id,
    sender.username AS remitente,
    sender.firstname AS remitente_nombre,
    sender.lastname AS remitente_apellido,
    mc.type AS tipo_conversacion,
    m.smallmessage AS mensaje_corto,
    m.fullmessage AS mensaje_completo,
    FROM_UNIXTIME(m.timecreated) AS fecha
FROM mdl_messages m
INNER JOIN mdl_user sender ON sender.id = m.useridfrom
INNER JOIN mdl_message_conversations mc ON mc.id = m.conversationid
WHERE sender.deleted = 0
ORDER BY m.timecreated DESC
LIMIT 50;

# 16.2 Notificaciones pendientes por usuario
SELECT 
    mc.id AS conversacion_id,
    CASE mc.type
        WHEN 1 THEN 'Individual'
        WHEN 2 THEN 'Grupal'
        WHEN 3 THEN 'Self'
    END AS tipo,
    sender.username AS remitente,
    sender.firstname AS nombre,
    m.smallmessage AS mensaje,
    FROM_UNIXTIME(m.timecreated) AS fecha,
    CASE 
        WHEN mua.action = 1 THEN 'Leído'
        ELSE 'No leído'
    END AS estado
FROM mdl_message_conversations mc
INNER JOIN mdl_messages m ON m.conversationid = mc.id
INNER JOIN mdl_user sender ON sender.id = m.useridfrom
LEFT JOIN mdl_message_user_actions mua ON mua.messageid = m.id 
    AND mua.userid <> m.useridfrom AND mua.action = 1
WHERE mc.id = 1
ORDER BY m.timecreated;

# 16.3 Participantes de cada conversación
SELECT 
    mc.id AS conversacion_id,
    mc.name AS nombre_conversacion,
    CASE mc.type
        WHEN 1 THEN 'Individual'
        WHEN 2 THEN 'Grupal'
        WHEN 3 THEN 'Self'
    END AS tipo,
    u.username,
    u.firstname,
    u.lastname
FROM mdl_message_conversations mc
INNER JOIN mdl_message_conversation_members mcm ON mcm.conversationid = mc.id
INNER JOIN mdl_user u ON u.id = mcm.userid
WHERE u.deleted = 0
ORDER BY mc.id, u.lastname;

# 16.4 Notificaciones pendientes por usuario
SELECT 
    u.username,
    u.firstname,
    u.lastname,
    COUNT(n.id) AS notificaciones_pendientes
FROM mdl_notifications n
INNER JOIN mdl_user u ON u.id = n.useridto
WHERE n.timeread IS NULL
  AND u.deleted = 0
GROUP BY u.id, u.username, u.firstname, u.lastname
ORDER BY notificaciones_pendientes DESC
LIMIT 20;

# 16.5 Últimas notificaciones con detalle
SELECT 
    n.id,
    sender.username AS de_usuario,
    receiver.username AS para_usuario,
    n.subject AS asunto,
    n.smallmessage AS mensaje,
    n.component,
    n.eventtype,
    FROM_UNIXTIME(n.timecreated) AS fecha_envio,
    FROM_UNIXTIME(n.timeread) AS fecha_leida,
    CASE 
        WHEN n.timeread IS NULL THEN 'No leída'
        ELSE 'Leída'
    END AS estado
FROM mdl_notifications n
INNER JOIN mdl_user sender ON sender.id = n.useridfrom
INNER JOIN mdl_user receiver ON receiver.id = n.useridto
WHERE receiver.deleted = 0
ORDER BY n.timecreated DESC
LIMIT 50;

# 16.6 Usuarios más activos en mensajería
SELECT 
    u.username,
    u.firstname,
    u.lastname,
    COUNT(m.id) AS mensajes_enviados,
    COUNT(DISTINCT m.conversationid) AS conversaciones_activas,
    MAX(FROM_UNIXTIME(m.timecreated)) AS ultimo_mensaje
FROM mdl_messages m
INNER JOIN mdl_user u ON u.id = m.useridfrom
WHERE u.deleted = 0
GROUP BY u.id, u.username, u.firstname, u.lastname
ORDER BY mensajes_enviados DESC
LIMIT 20;


################################################################### LECCIONES (LESSON) ##############################################################


# 17.1 Lecciones con páginas y progreso
SELECT 
    l.name AS leccion,
    c.fullname AS curso,
    lp.title AS pagina,
    CASE lp.qtype
        WHEN 1 THEN 'Pregunta respuesta corta'
        WHEN 2 THEN 'Verdadero/Falso'
        WHEN 3 THEN 'Opción múltiple'
        WHEN 5 THEN 'Emparejamiento'
        WHEN 10 THEN 'Ensayo'
        WHEN 20 THEN 'Página de contenido'
        WHEN 30 THEN 'Cluster'
        WHEN 31 THEN 'Fin de cluster'
    END AS tipo_pagina,
    lp.prevpageid,
    lp.nextpageid
FROM mdl_lesson l
INNER JOIN mdl_course c ON c.id = l.course
INNER JOIN mdl_lesson_pages lp ON lp.lessonid = l.id
WHERE l.course = 4
ORDER BY l.name, lp.id;



############################################################# GLOSARIOS ###############################################################


# 18.1 Entradas de glosario con autores
SELECT 
    g.name AS glosario,
    ge.concept AS concepto,
    ge.definition AS definicion,
    u.firstname,
    u.lastname,
    ge.approved AS aprobado,
    FROM_UNIXTIME(ge.timecreated) AS fecha_creacion,
    FROM_UNIXTIME(ge.timemodified) AS fecha_modificacion
FROM mdl_glossary g
INNER JOIN mdl_glossary_entries ge ON ge.glossaryid = g.id
INNER JOIN mdl_user u ON u.id = ge.userid
WHERE g.course = 4
ORDER BY g.name, ge.concept;


########################################################## WIKIS #######################################################
 
 
# 19.1 Páginas wiki con versiones
SELECT 
    w.name AS wiki,
    wp.title AS pagina,
    u.firstname AS autor_nombre,
    u.lastname AS autor_apellido,
    wp.cachedcontent,
    FROM_UNIXTIME(wp.timecreated) AS fecha_creacion,
    FROM_UNIXTIME(wp.timemodified) AS fecha_modificacion,
    (SELECT COUNT(*) FROM mdl_wiki_versions wv WHERE wv.pageid = wp.id) AS total_versiones
FROM mdl_wiki w
INNER JOIN mdl_wiki_subwikis ws ON ws.wikiid = w.id
INNER JOIN mdl_wiki_pages wp ON wp.subwikiid = ws.id
LEFT JOIN mdl_user u ON u.id = wp.userid
WHERE w.course = 4
ORDER BY w.name, wp.title;


####################################################### BLOQUES ################################################


# 20.1 Instancias de bloques por contexto
SELECT 
    bi.id,
    bi.blockname AS bloque,
    bi.pagetypepattern AS patron_pagina,
    bi.defaultregion AS region_defecto,
    bi.defaultweight AS peso_defecto,
    bi.showinsubcontexts,
    CASE ctx.contextlevel
        WHEN 10 THEN 'Sistema'
        WHEN 30 THEN 'Usuario'
        WHEN 40 THEN 'Categoría'
        WHEN 50 THEN 'Curso'
        WHEN 70 THEN 'Módulo'
    END AS nivel_contexto,
    bp.visible,
    bp.region AS region_pagina,
    bp.weight AS peso_pagina,
    FROM_UNIXTIME(bi.timecreated) AS fecha_creacion
FROM mdl_block_instances bi
INNER JOIN mdl_context ctx ON ctx.id = bi.parentcontextid
LEFT JOIN mdl_block_positions bp ON bp.blockinstanceid = bi.id
ORDER BY ctx.contextlevel, bi.blockname;

# 20.2 Bloques ocultos (visible = 0 en block_positions)
SELECT 
    bi.blockname AS bloque,
    bi.pagetypepattern AS patron_pagina,
    bp.pagetype,
    bp.visible,
    CASE ctx.contextlevel
        WHEN 10 THEN 'Sistema'
        WHEN 50 THEN 'Curso'
        WHEN 70 THEN 'Módulo'
    END AS nivel_contexto,
    ctx.instanceid
FROM mdl_block_instances bi
INNER JOIN mdl_block_positions bp ON bp.blockinstanceid = bi.id
INNER JOIN mdl_context ctx ON ctx.id = bi.parentcontextid
WHERE bp.visible = 0
ORDER BY bi.blockname;

# 20.3 Resumen: cuántas instancias tiene cada tipo de bloque
SELECT 
    bi.blockname AS bloque,
    COUNT(*) AS total_instancias,
    COUNT(DISTINCT bi.parentcontextid) AS contextos_distintos
FROM mdl_block_instances bi
GROUP BY bi.blockname
ORDER BY total_instancias DESC;


############################################################ CONSULTAS DE ANÁLISIS AVANZADO ##########################################

# 21.1 Dashboard completo: resumen general del sitio
SELECT 
    (SELECT COUNT(*) FROM mdl_user WHERE deleted = 0 AND suspended = 0) AS usuarios_activos,
    (SELECT COUNT(*) FROM mdl_course WHERE id > 1) AS total_cursos,
    (SELECT COUNT(*) FROM mdl_course WHERE id > 1 AND visible = 1) AS cursos_visibles,
    (SELECT COUNT(*) FROM mdl_course_categories) AS total_categorias,
    (SELECT COUNT(*) FROM mdl_user_enrolments WHERE status = 0) AS matriculaciones_activas,
    (SELECT COUNT(*) FROM mdl_course_modules) AS total_actividades,
    (SELECT COUNT(DISTINCT userid) FROM mdl_logstore_standard_log 
        WHERE timecreated >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 7 DAY))
    ) AS usuarios_activos_7dias,
    (SELECT ROUND(SUM(filesize) / 1073741824, 2) FROM mdl_files 
        WHERE filename <> '.' AND filesize > 0
    ) AS espacio_total_gb;

# 21.2 Tasa de abandono: matriculados que nunca accedieron al curso
SELECT 
    c.fullname AS curso,
    COUNT(DISTINCT ue.userid) AS total_matriculados,
    COUNT(DISTINCT l.userid) AS accedieron,
    COUNT(DISTINCT ue.userid) - COUNT(DISTINCT l.userid) AS nunca_accedieron,
    ROUND(
        (COUNT(DISTINCT ue.userid) - COUNT(DISTINCT l.userid)) / 
        COUNT(DISTINCT ue.userid) * 100, 1
    ) AS tasa_abandono_pct
FROM mdl_course c
INNER JOIN mdl_enrol e ON e.courseid = c.id
INNER JOIN mdl_user_enrolments ue ON ue.enrolid = e.id AND ue.status = 0
INNER JOIN mdl_user u ON u.id = ue.userid AND u.deleted = 0
LEFT JOIN mdl_logstore_standard_log l ON l.courseid = c.id AND l.userid = ue.userid
WHERE c.id > 1
GROUP BY c.id, c.fullname
HAVING total_matriculados > 0
ORDER BY tasa_abandono_pct DESC;

# 21.3 Engagement: actividad por hora del día
SELECT 
    HOUR(FROM_UNIXTIME(l.timecreated)) AS hora,
    COUNT(*) AS total_eventos,
    COUNT(DISTINCT l.userid) AS usuarios_unicos
FROM mdl_logstore_standard_log l
WHERE l.timecreated >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))
GROUP BY HOUR(FROM_UNIXTIME(l.timecreated))
ORDER BY hora;

# 21.4 Engagement: actividad por día de la semana
SELECT 
    DAYNAME(FROM_UNIXTIME(l.timecreated)) AS dia_semana,
    DAYOFWEEK(FROM_UNIXTIME(l.timecreated)) AS num_dia,
    COUNT(*) AS total_eventos,
    COUNT(DISTINCT l.userid) AS usuarios_unicos
FROM mdl_logstore_standard_log l
WHERE l.timecreated >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))
GROUP BY DAYNAME(FROM_UNIXTIME(l.timecreated)), DAYOFWEEK(FROM_UNIXTIME(l.timecreated))
ORDER BY num_dia;


# 21.5 Informe completo de un estudiante en un curso
SELECT 
    u.username,
    u.firstname,
    u.lastname,
    c.fullname AS curso,
    -- Calificación final
    ROUND(gg_course.finalgrade, 2) AS nota_final_curso,
    -- Completitud
    ROUND(
        (SELECT COUNT(*) FROM mdl_course_modules_completion cmc2 
         INNER JOIN mdl_course_modules cm2 ON cm2.id = cmc2.coursemoduleid
         WHERE cmc2.userid = u.id AND cm2.course = c.id AND cmc2.completionstate IN (1,2))
        /
        NULLIF((SELECT COUNT(*) FROM mdl_course_modules cm3 
                WHERE cm3.course = c.id AND cm3.completion > 0), 0) * 100, 1
    ) AS pct_completitud,
    -- Actividad en logs
    (SELECT COUNT(*) FROM mdl_logstore_standard_log l 
     WHERE l.userid = u.id AND l.courseid = c.id) AS total_acciones,
    (SELECT COUNT(DISTINCT DATE(FROM_UNIXTIME(l2.timecreated))) 
     FROM mdl_logstore_standard_log l2 
     WHERE l2.userid = u.id AND l2.courseid = c.id) AS dias_activos,
    (SELECT MAX(FROM_UNIXTIME(l3.timecreated)) 
     FROM mdl_logstore_standard_log l3 
     WHERE l3.userid = u.id AND l3.courseid = c.id) AS ultimo_acceso_curso,
    -- Posts en foros
    (SELECT COUNT(*) FROM mdl_forum_posts fp 
     INNER JOIN mdl_forum_discussions fd ON fd.id = fp.discussion
     INNER JOIN mdl_forum f ON f.id = fd.forum
     WHERE fp.userid = u.id AND f.course = c.id) AS posts_foros
FROM mdl_user u
INNER JOIN mdl_user_enrolments ue ON ue.userid = u.id
INNER JOIN mdl_enrol e ON e.id = ue.enrolid
INNER JOIN mdl_course c ON c.id = e.courseid
LEFT JOIN mdl_grade_grades gg_course ON gg_course.userid = u.id
    AND gg_course.itemid = (
        SELECT gi.id FROM mdl_grade_items gi 
        WHERE gi.courseid = c.id AND gi.itemtype = 'course' LIMIT 1
    )
WHERE u.id = 2
  AND c.id = 4;


# 21.6 Ranking de estudiantes por curso (tabla de posiciones)
SELECT 
    @rownum := @rownum + 1 AS posicion,
    sub.username,
    sub.firstname,
    sub.lastname,
    sub.nota_final,
    sub.nota_maxima,
    sub.porcentaje
FROM (
    SELECT 
        u.username,
        u.firstname,
        u.lastname,
        ROUND(gg.finalgrade, 2) AS nota_final,
        ROUND(gi.grademax, 2) AS nota_maxima,
        ROUND(gg.finalgrade / gi.grademax * 100, 1) AS porcentaje
    FROM mdl_grade_grades gg
    INNER JOIN mdl_grade_items gi ON gi.id = gg.itemid
    INNER JOIN mdl_user u ON u.id = gg.userid
    WHERE gi.courseid = 4
      AND gi.itemtype = 'course'
      AND gg.finalgrade IS NOT NULL
      AND u.deleted = 0
    ORDER BY gg.finalgrade DESC
) sub, (SELECT @rownum := 0) r;


# 21.7 Cursos más populares (por matriculación y actividad)
SELECT 
    c.id,
    c.fullname AS curso,
    cc.name AS categoria,
    COUNT(DISTINCT ue.userid) AS matriculados,
    (SELECT COUNT(*) FROM mdl_logstore_standard_log l 
     WHERE l.courseid = c.id 
     AND l.timecreated >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))
    ) AS eventos_30dias,
    (SELECT COUNT(DISTINCT l2.userid) FROM mdl_logstore_standard_log l2 
     WHERE l2.courseid = c.id 
     AND l2.timecreated >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))
    ) AS usuarios_activos_30dias
FROM mdl_course c
INNER JOIN mdl_course_categories cc ON cc.id = c.category
LEFT JOIN mdl_enrol e ON e.courseid = c.id
LEFT JOIN mdl_user_enrolments ue ON ue.enrolid = e.id AND ue.status = 0
WHERE c.id > 1
GROUP BY c.id, c.fullname, cc.name
ORDER BY matriculados DESC
LIMIT 20;

####################################################### MANTENIMIENTO Y DIAGNÓSTICO #######################################

# 22.1 Usuarios duplicados por email
SELECT 
    u.email,
    COUNT(*) AS total,
    GROUP_CONCAT(u.username ORDER BY u.id SEPARATOR ', ') AS usernames,
    GROUP_CONCAT(u.id ORDER BY u.id SEPARATOR ', ') AS ids
FROM mdl_user u
WHERE u.deleted = 0
  AND u.email <> ''
GROUP BY u.email
HAVING total > 1
ORDER BY total DESC;


# 22.2 Tablas más grandes de la base de datos
SELECT 
    TABLE_NAME AS tabla,
    TABLE_ROWS AS filas_estimadas,
    ROUND(DATA_LENGTH / 1048576, 2) AS datos_mb,
    ROUND(INDEX_LENGTH / 1048576, 2) AS indices_mb,
    ROUND((DATA_LENGTH + INDEX_LENGTH) / 1048576, 2) AS total_mb
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME LIKE 'mdl_%'
ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC
LIMIT 20;

# 22.3 Sesiones huérfanas (usuario eliminado)
SELECT 
    s.id AS session_id,
    s.userid,
    s.sid,
    FROM_UNIXTIME(s.timecreated) AS creada
FROM mdl_sessions s
LEFT JOIN mdl_user u ON u.id = s.userid
WHERE u.id IS NULL OR u.deleted = 1;

# 22.4 Matriculaciones huérfanas
SELECT 
    ue.id,
    ue.userid,
    ue.enrolid,
    e.courseid,
    e.enrol AS metodo
FROM mdl_user_enrolments ue
INNER JOIN mdl_enrol e ON e.id = ue.enrolid
LEFT JOIN mdl_user u ON u.id = ue.userid
WHERE u.id IS NULL OR u.deleted = 1;

# 22.5 Tareas cron pendientes/fallidas
SELECT 
    classname,
    component,
    nextruntime,
    FROM_UNIXTIME(nextruntime) AS proxima_ejecucion,
    FROM_UNIXTIME(lastruntime) AS ultima_ejecucion,
    faildelay AS retraso_fallo,
    disabled
FROM mdl_task_scheduled
WHERE disabled = 0
ORDER BY nextruntime;

# 22.6 Verificar integridad: roles asignados sin contexto válido
SELECT 
    ra.id,
    ra.roleid,
    ra.userid,
    ra.contextid,
    r.shortname AS rol
FROM mdl_role_assignments ra
INNER JOIN mdl_role r ON r.id = ra.roleid
LEFT JOIN mdl_context ctx ON ctx.id = ra.contextid
WHERE ctx.id IS NULL;













