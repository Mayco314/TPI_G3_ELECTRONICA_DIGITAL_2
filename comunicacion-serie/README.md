# Comunicación serie

Este documento describe el protocolo de comunicación serie entre el PIC16F887 (módulo EUSART) y la interfaz gráfica en la PC. Está en desarrollo: lo que todavía no está decidido figura como **a definir** y se resume en la sección 4.

## 1. Parámetros físicos

| Parámetro | Valor |
|-----------|-------|
| Módulo | EUSART (modo asincrónico) |
| Pines | RC6 = TX, RC7 = RX |
| Velocidad | 9600 baudios |
| Formato de trama | 8N1: 1 bit de start, 8 bits de datos, sin paridad, 1 bit de stop |
| Codificación | NRZ, LSB primero, línea en alto en reposo |
| Niveles lógicos | TTL |
| Fin de línea (PIC → PC) | CR + LF (`\r\n`, `0x0D 0x0A`) |

Cada byte viaja en 10 bits (start + 8 datos + stop), por lo que tarda aproximadamente **1,04 ms** a 9600 baudios.

Conexión: TX del PIC al RX del adaptador USB-UART y RX del PIC al TX del adaptador (cruzados), con GND en común.

## 2. PIC → PC (datos de sensores)

### Funcionamiento

1. Se realiza el sensado de un sensor (primero el sensor 1, luego el sensor 2).
2. El dato se convierte en tres dígitos: centena (C), decena (D) y unidad (U).
3. Cada dígito se pasa a ASCII (se le suma 48, es decir `0x30`).
4. Se envían los tres dígitos uno a uno y se cierra con CR y LF.
5. Se repite el mismo proceso para el otro sensor.

El sensado está previsto con Timer0: cada desborde dispara un ciclo de medición y envío.

### Formato del mensaje

| Byte | Contenido | Valores |
|------|-----------|---------|
| 1 | Centena | `'0'`–`'9'` (`0x30`–`0x39`) |
| 2 | Decena | `'0'`–`'9'` (`0x30`–`0x39`) |
| 3 | Unidad | `'0'`–`'9'` (`0x30`–`0x39`) |
| 4 | CR | `0x0D` |
| 5 | LF | `0x0A` |


### Secuencia de un ciclo

```
C1 -> D1 -> U1 -> CR -> LF -> C2 -> D2 -> U2 -> CR -> LF
|__________ sensor 1 ______| |__________ sensor 2 ______|
```

Orden fijo: sensor 1 = LM35, sensor 2 = LDR.

### Tiempos

| Elemento | Bytes | Tiempo aproximado |
|----------|-------|-------------------|
| Un byte | 1 | 1,04 ms |
| Mensaje de un sensor | 5 | 5,2 ms |
| Ciclo completo (2 sensores) | 10 | 10,4 ms |

El período entre ciclos lo marca Timer0 y debe ser mayor que el tiempo del ciclo completo. Valor a definir.

## 3. PC → PIC (comandos)

### Funcionamiento

1. Se presiona una tecla en la interfaz.
2. La interfaz envía al PIC **un solo byte** con el código ASCII de la tecla (en mayúscula).
3. El PIC compara el byte recibido con los valores conocidos y, si coincide, activa los motores según corresponda.

Los comandos son de un solo byte y no llevan fin de línea.

### Teclas

| Tecla | Byte | Hex | Acción (preliminar) |
|-------|------|-----|---------------------|
| W | `'W'` | `0x57` | Avanzar |
| A | `'A'` | `0x41` | Girar a la izquierda |
| S | `'S'` | `0x53` | Retroceder |
| D | `'D'` | `0x44` | Girar a la derecha |
| X | `'X'` | `0x58` | Frenar (a definir) |

### Comportamiento (preliminar)

- Idea 1: El robot se mueve mientras la tecla está presionada y frena al soltarla.
- Idea 2: movimiento constante hasta presionar X.

### Tiempo

Un comando ocupa 1 byte: aproximadamente **1,04 ms**.

## 4. A definir

- [ ] Identificador de sensor en el mensaje (hoy se asume orden fijo LM35 → LDR)
- [ ] Período de muestreo y envío (Timer0)
- [ ] Byte de frenado y mecanismo de parada (al soltar la tecla o repetición)
- [ ] Modo de movimiento constante hasta presionar X
