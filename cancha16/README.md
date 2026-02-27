# 🏟️ Cancha de la 16 — Sistema de Reservas

> Panel de reservas para cancha sintética con frontend AMN, backend Supabase y precios dinámicos.

---

## 📁 Estructura del proyecto

```
cancha16/
│
├── public/                    ← Archivos que van al hosting (Vercel / Netlify / cualquier CDN)
│   ├── index.html             ← Frontend cliente (landing + reservas + eventos + fijos)
│   └── admin.html             ← Panel admin con PIN (agenda + gestión + finanzas)
│
├── src/
│   ├── lib/
│   │   ├── supabase.js        ← Cliente Supabase singleton
│   │   ├── api.js             ← Todas las queries a Supabase organizadas por módulo
│   │   └── utils.js           ← Helpers de fecha, precio, UI (sin dependencias)
│   └── (cliente_script.html  ← Script fuente del cliente — ya compilado en public/)
│       (admin_script.html    ← Script fuente del admin  — ya compilado en public/)
│
└── supabase/
    └── migrations/
        └── 001_initial.sql    ← Schema completo: tablas, RLS, funciones, triggers
```

> **Los archivos listos para deploy son `public/index.html` y `public/admin.html`.**  
> El directorio `src/` es para referencia y modificaciones futuras.

---

## 🚀 Setup en 5 pasos

### 1. Crear proyecto en Supabase

1. Ve a [supabase.com](https://supabase.com) → New project
2. Anota tu **Project URL** y **anon public key** (Settings → API)

### 2. Ejecutar el schema

En el SQL Editor de Supabase, ejecuta el archivo completo:

```
supabase/migrations/001_initial.sql
```

Esto crea:
- Tablas: `perfiles`, `franjas_precio`, `horarios_operativos`, `reservas`, `clientes_fijos`, `eventos`, `productos`, `ventas_productos`, `config_pago`
- Funciones: `stats_dia()`, `calcular_precio()`, `slots_ocupados()`
- Políticas RLS para lectura pública / escritura admin
- Bucket `comprobantes` en Storage
- Trigger auto-creación de perfil al registrarse

### 3. Configurar credenciales

Edita **ambos HTMLs** (en el `<script>` al final, bloque `window.ENV`):

```javascript
// En public/index.html y public/admin.html
window.ENV = {
  SUPABASE_URL:      'https://XXXXXXXX.supabase.co',   // ← Tu URL
  SUPABASE_ANON_KEY: 'eyJhbGciOiJ...',                 // ← Tu anon key
  WA_NUM:            '573001234567',                    // ← WhatsApp sin +
  ADMIN_PIN:         '1234',                            // ← PIN del admin (solo en admin.html)
}
```

### 4. Deploy (opción más simple: Netlify)

```bash
# Arrastra la carpeta /public a netlify.com/drop
# O conecta el repo a Netlify/Vercel apuntando a /public como directorio raíz
```

### 5. Crear usuario admin (opcional para auth real)

En Supabase → Authentication → Add user, crea el usuario admin.  
Luego en SQL Editor:
```sql
UPDATE perfiles SET rol = 'admin' WHERE id = 'UUID_DEL_USUARIO';
```

---

## ⚙️ Variables de entorno (window.ENV)

| Variable         | Dónde               | Descripción                          |
|------------------|---------------------|--------------------------------------|
| `SUPABASE_URL`   | index + admin       | URL del proyecto Supabase            |
| `SUPABASE_ANON_KEY` | index + admin    | Clave pública (anon)                 |
| `WA_NUM`         | index.html          | Número WhatsApp sin `+` ni espacios  |
| `ADMIN_PIN`      | admin.html          | PIN de 4 dígitos para acceder        |

---

## 🗄️ Tablas principales

| Tabla               | Descripción                                      |
|---------------------|--------------------------------------------------|
| `reservas`          | Todas las reservas. GIST constraint anti-overlap |
| `clientes_fijos`    | Cupos fijos por día/hora. `solicitud→activo`     |
| `franjas_precio`    | Precios editables por franja × tipo de día       |
| `horarios_operativos` | Apertura/cierre por día de semana             |
| `eventos`           | Torneos, cumpleaños, campeonatos                 |
| `productos`         | Tienda: agua, bebidas, balones                   |
| `ventas_productos`  | Registro de ventas de tienda                     |
| `config_pago`       | Nequi, banco, titular, instrucciones             |

---

## 🔄 Tiempo real (Supabase Realtime)

- **Cliente**: Se suscribe a `reservas` filtrado por fecha al seleccionar un día. Si alguien más reserva, los slots se actualizan solos sin recargar.
- **Admin**: Se suscribe a `INSERT` en `reservas` para mostrar toast de nueva reserva.

---

## 💰 Lógica de precios

Los precios se cargan desde `franjas_precio` en Supabase:

```
Franja   | Horas      | Lun–Jue  | Vie      | Sáb–Dom
---------|------------|----------|----------|--------
Mañana   | 07–12h     | $50.000  | $60.000  | $65.000
Tarde    | 12–18h     | $65.000  | $75.000  | $80.000
Noche    | 18–23h     | $80.000  | $90.000  | $100.000
```

El admin puede editar estos valores en **Cancha → Precios por Franja** y se actualizan al instante.

---

## 🔒 Seguridad

- RLS habilitado en todas las tablas
- Clientes solo pueden `INSERT` reservas en estado `pendiente`
- Admin necesita `rol = 'admin'` en `perfiles` para `UPDATE`/`DELETE`
- El PIN del admin es una capa visual; la seguridad real viene de Supabase RLS
- Comprobantes en bucket privado `comprobantes` (no acceso público)

---

## 📱 Flujo del cliente

```
Landing → Tabla precios → Selector de día → Elige slot → Modal paso 1 (resumen)
→ Paso 2 (método pago: Nequi / Bancolombia / Efectivo)
→ Paso 3 (sube comprobante) → Reserva creada en estado PENDIENTE
→ Admin confirma → Cliente notificado (WhatsApp manual o integración futura)
```

## 🛠️ Flujo del admin

```
Login PIN → Agenda del día (cronograma hora a hora)
→ Confirmar/Cancelar/Liberar reservas
→ Clientes Fijos: aprobar solicitudes o registrar manual
→ Finanzas: registrar ventas de tienda, ver ingresos
→ Configuración: editar precios, horarios, datos de pago
```

---

## 🔮 Próximos pasos sugeridos

- [ ] Notificaciones WhatsApp automáticas vía Twilio o Meta API al confirmar/cancelar
- [ ] Email con comprobante de reserva (Supabase Edge Functions + Resend)
- [ ] Login real para clientes (historial de reservas)
- [ ] Dashboard de estadísticas con queries reales sobre todos los meses
- [ ] PWA (Progressive Web App) para instalar en celular
