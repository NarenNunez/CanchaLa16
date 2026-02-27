-- ═══════════════════════════════════════════════════════════════
--  CANCHA DE LA 16 · Schema inicial
--  Supabase PostgreSQL
-- ═══════════════════════════════════════════════════════════════

-- Extensiones necesarias
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ───────────────────────────────────────────────────────────────
--  1. PERFILES (admin y clientes)
-- ───────────────────────────────────────────────────────────────
CREATE TABLE perfiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre      TEXT,
  telefono    TEXT,
  rol         TEXT NOT NULL DEFAULT 'cliente' CHECK (rol IN ('admin','cliente')),
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- Auto-crear perfil al registrarse
CREATE OR REPLACE FUNCTION crear_perfil_nuevo_usuario()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO perfiles (id, nombre, telefono, rol)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'nombre', ''),
    COALESCE(NEW.raw_user_meta_data->>'telefono', ''),
    'cliente'
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION crear_perfil_nuevo_usuario();

-- ───────────────────────────────────────────────────────────────
--  2. CONFIGURACIÓN DE PRECIOS
--  Permite al admin cambiar precios por franja × tipo de día
-- ───────────────────────────────────────────────────────────────
CREATE TABLE franjas_precio (
  id           SERIAL PRIMARY KEY,
  nombre       TEXT NOT NULL,                -- 'Mañana', 'Tarde', 'Noche'
  hora_inicio  SMALLINT NOT NULL,            -- 7, 12, 18
  hora_fin     SMALLINT NOT NULL,            -- 12, 18, 23
  precio_lv    INTEGER NOT NULL,             -- Lunes–Jueves (COP)
  precio_vie   INTEGER NOT NULL,             -- Viernes
  precio_fsd   INTEGER NOT NULL,             -- Sábado–Domingo
  activo       BOOLEAN DEFAULT true,
  updated_at   TIMESTAMPTZ DEFAULT now()
);

-- Datos iniciales
INSERT INTO franjas_precio (nombre, hora_inicio, hora_fin, precio_lv, precio_vie, precio_fsd) VALUES
  ('Mañana',  7,  12, 50000, 60000,  65000),
  ('Tarde',  12,  18, 65000, 75000,  80000),
  ('Noche',  18,  23, 80000, 90000, 100000);

-- ───────────────────────────────────────────────────────────────
--  3. HORARIOS OPERATIVOS
-- ───────────────────────────────────────────────────────────────
CREATE TABLE horarios_operativos (
  id           SERIAL PRIMARY KEY,
  dia_semana   SMALLINT NOT NULL UNIQUE CHECK (dia_semana BETWEEN 0 AND 6), -- 0=Dom
  apertura     TIME NOT NULL DEFAULT '07:00',
  cierre       TIME NOT NULL DEFAULT '23:00',
  activo       BOOLEAN DEFAULT true
);

INSERT INTO horarios_operativos (dia_semana, apertura, cierre) VALUES
  (0, '08:00', '22:00'),
  (1, '07:00', '23:00'),
  (2, '07:00', '23:00'),
  (3, '07:00', '23:00'),
  (4, '07:00', '23:00'),
  (5, '07:00', '23:00'),
  (6, '08:00', '23:00');

-- ───────────────────────────────────────────────────────────────
--  4. RESERVAS
--  Constraint GIST evita double-booking a nivel de base de datos
-- ───────────────────────────────────────────────────────────────
CREATE TABLE reservas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_nombre  TEXT NOT NULL,
  cliente_tel     TEXT,
  fecha           DATE NOT NULL,
  hora_inicio     TIME NOT NULL,
  hora_fin        TIME NOT NULL,
  precio          INTEGER NOT NULL DEFAULT 0,
  metodo_pago     TEXT CHECK (metodo_pago IN ('nequi','bancolombia','efectivo')),
  tipo            TEXT NOT NULL DEFAULT 'normal' CHECK (tipo IN ('normal','fijo','bloqueo','evento')),
  estado          TEXT NOT NULL DEFAULT 'pendiente'
                    CHECK (estado IN ('pendiente','confirmado','cancelado','bloqueado')),
  comprobante_url TEXT,
  notas           TEXT,
  -- Rango temporal para el constraint de solapamiento
  rango           TSRANGE GENERATED ALWAYS AS (
                    tsrange(fecha::timestamp + hora_inicio, fecha::timestamp + hora_fin)
                  ) STORED,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),

  -- ★ ANTI-DOUBLE-BOOKING: imposible crear dos reservas que se solapan
  EXCLUDE USING GIST (rango WITH &&)
    WHERE (estado NOT IN ('cancelado'))
);

CREATE INDEX idx_reservas_fecha   ON reservas (fecha);
CREATE INDEX idx_reservas_estado  ON reservas (estado);
CREATE INDEX idx_reservas_tipo    ON reservas (tipo);
CREATE INDEX idx_reservas_rango   ON reservas USING GIST (rango);

-- Auto-updated_at
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TRIGGER trg_reservas_updated_at
  BEFORE UPDATE ON reservas
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────────
--  5. CLIENTES FIJOS
-- ───────────────────────────────────────────────────────────────
CREATE TABLE clientes_fijos (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre         TEXT NOT NULL,
  telefono       TEXT,
  dia_semana     SMALLINT NOT NULL CHECK (dia_semana BETWEEN 0 AND 6),
  hora_inicio    TIME NOT NULL,
  hora_fin       TIME NOT NULL,
  personas       SMALLINT DEFAULT 10,
  descuento_pct  SMALLINT DEFAULT 10 CHECK (descuento_pct BETWEEN 0 AND 100),
  estado         TEXT NOT NULL DEFAULT 'solicitud'
                   CHECK (estado IN ('solicitud','activo','inactivo')),
  notas          TEXT,
  created_at     TIMESTAMPTZ DEFAULT now(),
  updated_at     TIMESTAMPTZ DEFAULT now()
);

CREATE TRIGGER trg_fijos_updated_at
  BEFORE UPDATE ON clientes_fijos
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────────
--  6. EVENTOS
-- ───────────────────────────────────────────────────────────────
CREATE TABLE eventos (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  titulo       TEXT NOT NULL,
  tipo         TEXT NOT NULL DEFAULT 'otro'
                 CHECK (tipo IN ('torneo','cumpleanos','campeonato','corporativo','otro')),
  descripcion  TEXT,
  fecha_inicio TIMESTAMPTZ,
  fecha_fin    TIMESTAMPTZ,
  precio       INTEGER DEFAULT 0,
  cupos_total  SMALLINT DEFAULT 10,
  cupos_ocupados SMALLINT DEFAULT 0,
  estado       TEXT NOT NULL DEFAULT 'activo'
                 CHECK (estado IN ('activo','cerrado','cancelado')),
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now()
);

CREATE TRIGGER trg_eventos_updated_at
  BEFORE UPDATE ON eventos
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────────
--  7. PRODUCTOS / TIENDA
-- ───────────────────────────────────────────────────────────────
CREATE TABLE productos (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre     TEXT NOT NULL,
  emoji      TEXT DEFAULT '📦',
  precio     INTEGER NOT NULL,
  stock      SMALLINT DEFAULT 0,
  activo     BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE ventas_productos (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  producto_id UUID REFERENCES productos(id),
  cantidad    SMALLINT NOT NULL DEFAULT 1,
  precio_unit INTEGER NOT NULL,
  total       INTEGER GENERATED ALWAYS AS (cantidad * precio_unit) STORED,
  notas       TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_ventas_fecha ON ventas_productos (created_at);

-- ───────────────────────────────────────────────────────────────
--  8. DATOS DE PAGO (configuración del admin)
-- ───────────────────────────────────────────────────────────────
CREATE TABLE config_pago (
  id              SERIAL PRIMARY KEY,
  nequi_numero    TEXT,
  banco_nombre    TEXT DEFAULT 'Bancolombia',
  banco_cuenta    TEXT,
  banco_titular   TEXT,
  instrucciones   TEXT,
  updated_at      TIMESTAMPTZ DEFAULT now()
);

INSERT INTO config_pago (nequi_numero, banco_nombre, banco_cuenta, banco_titular, instrucciones)
VALUES (
  '+57 300 123 4567',
  'Bancolombia',
  '123-456789-00',
  'Cancha de la 16 S.A.S.',
  'Realiza la transferencia y sube el comprobante. Confirmamos en máximo 1 hora.'
);

-- ───────────────────────────────────────────────────────────────
--  9. FUNCIONES DE UTILIDAD
-- ───────────────────────────────────────────────────────────────

-- Retorna los slots ocupados para una fecha dada
CREATE OR REPLACE FUNCTION slots_ocupados(p_fecha DATE)
RETURNS TABLE (hora_inicio TIME, hora_fin TIME, tipo TEXT, estado TEXT)
LANGUAGE sql STABLE AS $$
  SELECT hora_inicio, hora_fin, tipo, estado
  FROM reservas
  WHERE fecha = p_fecha
    AND estado NOT IN ('cancelado')
  ORDER BY hora_inicio;
$$;

-- Calcula el precio para una hora y día de semana
CREATE OR REPLACE FUNCTION calcular_precio(p_hora SMALLINT, p_dow SMALLINT)
RETURNS INTEGER LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN p_dow IN (6, 0) THEN precio_fsd   -- Sáb, Dom
    WHEN p_dow = 5       THEN precio_vie   -- Vie
    ELSE                      precio_lv    -- Lun–Jue
  END
  FROM franjas_precio
  WHERE activo = true
    AND p_hora >= hora_inicio
    AND p_hora < hora_fin
  LIMIT 1;
$$;

-- Estadísticas rápidas para el dashboard
CREATE OR REPLACE FUNCTION stats_dia(p_fecha DATE)
RETURNS JSON LANGUAGE sql STABLE AS $$
  SELECT json_build_object(
    'total',      COUNT(*) FILTER (WHERE tipo != 'bloqueo'),
    'pendientes', COUNT(*) FILTER (WHERE estado = 'pendiente'),
    'confirmados',COUNT(*) FILTER (WHERE estado = 'confirmado'),
    'bloqueados', COUNT(*) FILTER (WHERE tipo = 'bloqueo'),
    'ingresos',   COALESCE(SUM(precio) FILTER (WHERE estado = 'confirmado'), 0)
  )
  FROM reservas
  WHERE fecha = p_fecha;
$$;

-- ───────────────────────────────────────────────────────────────
--  10. STORAGE (bucket para comprobantes)
-- ───────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public) VALUES ('comprobantes', 'comprobantes', false);

-- ───────────────────────────────────────────────────────────────
--  11. RLS (Row Level Security)
-- ───────────────────────────────────────────────────────────────

-- Reservas: clientes pueden crear, admin puede todo
ALTER TABLE reservas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Reservas: lectura pública de slots ocupados"
  ON reservas FOR SELECT
  USING (true);

CREATE POLICY "Reservas: cualquiera puede crear (pendiente)"
  ON reservas FOR INSERT
  WITH CHECK (estado = 'pendiente');

CREATE POLICY "Reservas: solo admin puede actualizar/eliminar"
  ON reservas FOR UPDATE
  USING (EXISTS (SELECT 1 FROM perfiles WHERE id = auth.uid() AND rol = 'admin'));

CREATE POLICY "Reservas: solo admin puede eliminar"
  ON reservas FOR DELETE
  USING (EXISTS (SELECT 1 FROM perfiles WHERE id = auth.uid() AND rol = 'admin'));

-- Clientes fijos
ALTER TABLE clientes_fijos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Fijos: lectura pública (para mostrar slots bloqueados)"
  ON clientes_fijos FOR SELECT USING (true);

CREATE POLICY "Fijos: cualquiera puede solicitar"
  ON clientes_fijos FOR INSERT
  WITH CHECK (estado = 'solicitud');

CREATE POLICY "Fijos: solo admin gestiona"
  ON clientes_fijos FOR UPDATE
  USING (EXISTS (SELECT 1 FROM perfiles WHERE id = auth.uid() AND rol = 'admin'));

-- Franjas de precio: lectura pública, escritura solo admin
ALTER TABLE franjas_precio ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Precios: lectura pública" ON franjas_precio FOR SELECT USING (true);
CREATE POLICY "Precios: solo admin edita" ON franjas_precio FOR UPDATE
  USING (EXISTS (SELECT 1 FROM perfiles WHERE id = auth.uid() AND rol = 'admin'));

-- Productos: lectura pública
ALTER TABLE productos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Productos: lectura pública" ON productos FOR SELECT USING (activo = true);
CREATE POLICY "Productos: admin gestiona" ON productos FOR ALL
  USING (EXISTS (SELECT 1 FROM perfiles WHERE id = auth.uid() AND rol = 'admin'));

-- Ventas: solo admin
ALTER TABLE ventas_productos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Ventas: solo admin" ON ventas_productos FOR ALL
  USING (EXISTS (SELECT 1 FROM perfiles WHERE id = auth.uid() AND rol = 'admin'));

-- Eventos: lectura pública
ALTER TABLE eventos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Eventos: lectura pública" ON eventos FOR SELECT USING (estado = 'activo');
CREATE POLICY "Eventos: admin gestiona" ON eventos FOR ALL
  USING (EXISTS (SELECT 1 FROM perfiles WHERE id = auth.uid() AND rol = 'admin'));

-- Config pago: lectura pública (para mostrar instrucciones), escritura admin
ALTER TABLE config_pago ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Config pago: lectura pública" ON config_pago FOR SELECT USING (true);
CREATE POLICY "Config pago: solo admin edita" ON config_pago FOR UPDATE
  USING (EXISTS (SELECT 1 FROM perfiles WHERE id = auth.uid() AND rol = 'admin'));
