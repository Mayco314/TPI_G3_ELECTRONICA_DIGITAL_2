# Prueba de comunicación serie
 
Programa de prueba, a escala reducida, de la comunicación serie entre el PIC16F887 y la interfaz en la PC. Contiene las bases de lo que se va a desarrollar a mayor escala en el firmware final.
 
> **Estado:** transmisión, recepción y timeout de comandos funcionando en simulación (Proteus), probados también con la interfaz gráfica **Ariadna** a través de un par de puertos serie virtuales. Pendiente: comandos A y D en el PIC, segundo sensor e integración con el resto de los módulos.
 
## Objetivo
 
Verificar que la comunicación serie funciona de acuerdo al [protocolo del proyecto](../README.md) y con la interfaz de la PC ([Ariadna](ariadna_gui.py)), antes de integrarla con el resto de las partes (motores, sensores y ADC).
 
## Parámetros
 
| Parámetro | Valor |
|-----------|-------|
| Oscilador | Cristal de 4 MHz (XT) |
| EUSART | 9600 baudios, 8N1 (`SPBRG = 25`, `BRGH = 1`) |
| Pines | RC6 = TX, RC7 = RX |
| Tick del Timer0 | 10 ms (prescaler 1:256, offset 217) |
| Transmisión | Cada 100 ticks (1 s) |
| Timeout de comandos | 30 ticks (300 ms) |
| LEDs de prueba | RD2 y RD3 |
 
 
## Cómo funciona
 
El programa trabaja con dos interrupciones (Timer0 y recepción serie).
 
### Transmisión (PIC → PC), una vez por segundo
 
1. El Timer0 desborda cada 10 ms y cada desborde suma 1 a un contador.
2. Al llegar a 100 (100 × 10 ms = 1 s), se transmite el valor sensado.
3. El valor está guardado en tres variables, una por dígito (centena, decena y unidad), cada una de 0 a 9. Cada dígito se pasa a ASCII sumándole 48 (el código del carácter `'0'`) y se envía como un byte. Al final se envían CR y LF.
Ejemplo con el valor 123:
 
| Byte | 1 | 2 | 3 | 4 | 5 |
|------|---|---|---|---|---|
| Carácter | `1` | `2` | `3` | CR | LF |
| Hex | `0x31` | `0x32` | `0x33` | `0x0D` | `0x0A` |
 
Mientras no esté integrado el módulo del ADC, las variables de los dígitos valen 0 y se transmite `000`. El formato se verificó con el valor fijo 123.
 
### Recepción (PC → PIC)
 
1. Cada byte recibido genera una interrupción.
2. El PIC lo guarda en `REG_RX` y lo compara con los comandos conocidos.
3. Si es un comando válido, guarda el estado de movimiento en `ESTADO_MOVIMIENTO` y reinicia el contador del timeout. Un byte desconocido se ignora.
4. El MAIN LOOP lee `ESTADO_MOVIMIENTO` y actúa sobre las salidas: en esta prueba, los LEDs; en el firmware final, los motores.

| `ESTADO_MOVIMIENTO` | Comando | Acción en la prueba |
|---------------------|---------|---------------------|
| 0 | (ninguno) | LEDs apagados (quieto) |
| 1 | `W` (`0x57`) | Enciende RD2 (adelante) |
| 2 | `S` (`0x53`) | Enciende RD3 (atrás) |
 
Pendiente: `A` (`0x41`) y `D` (`0x44`).
 
### Timeout de comandos
 
El robot se mueve **mientras la interfaz repite el comando de la tecla mantenida** y se detiene al soltarla. El PIC no recibe ningún aviso al soltar la tecla: lo detecta porque dejan de llegar comandos.
 
- La interfaz repite el comando cada **100 ms** mientras la tecla está presionada.
- Al mantener una tecla en la terminal de Proteus, la repetición automática del teclado depende de la configuración del sistema operativo. Por eso la interfaz (Ariadna) usa su propio temporizador de 100 ms y no depende de esa repetición.
- El PIC suma 1 a un contador en cada tick de 10 ms y lo reinicia con cada comando válido. Si llega a **30 ticks (300 ms)**, vuelve al estado quieto.
- 300 ms es el triple del período de repetición, para tolerar retardos de la PC y del adaptador USB. Como consecuencia, el robot frena entre 200 y 300 ms después de soltar la tecla.
- También frena solo si se corta la comunicación o se cierra la interfaz.
- Con 10 bytes/s a 9600 baudios (≈1,04 ms por byte) se usa cerca del 1 % del enlace, por lo que no hay riesgo de saturar el receptor.

## Contenido de la carpeta
 
| Elemento | Descripción |
|----------|-------------|
| Proyecto MPLAB X | Código en assembler (MPASM) para el PIC16F887 |
| Proyecto de Proteus | Circuito para simular la prueba |
| [`../ariadna_gui.py`](ariadna_gui.py) | Interfaz gráfica de la PC (Ariadna) |
 
## Interfaz Ariadna
 
Interfaz en Python (Tkinter, matplotlib y pyserial), adaptada del script `plotter_serial.py` de la cátedra. Muestra el dato recibido de Teseo (valor numérico e historial en un gráfico) y envía al PIC la tecla **W, A, S o D** mientras se mantiene presionada.
 
- **Datos de Teseo:** lee una línea por segundo (`ddd` + CR + LF), extrae el número y lo muestra y grafica.
- **Envío de comandos:** repite el byte ASCII de la tecla cada **100 ms** mientras está presionada (período de repetición que espera el timeout del PIC). Al soltarla, deja de enviar.
- **Mensaje en pantalla:** al presionar una tecla válida aparece "Ariadna está guiando a Teseo" con la dirección.
- **Seguridad:** si la ventana pierde el foco o se pausa la conexión, se sueltan todas las teclas y no se envía nada.
- **Botones:** CONECTAR, PAUSAR y SALIR.
- **Configuración:** en el encabezado del archivo, `PORT` (por defecto `COM3`) y `BAUD_RATE = 9600`.
 
> La interfaz ya envía `A` y `D`, pero el PIC de esta prueba todavía los ignora.
 
## Cómo probarlo
 
1. En MPLAB X (v5.35) hacer **Clean and Build** para generar el `.hex`, que queda en `dist/`
2. En Proteus, abrir el circuito, conectar la Terminal Virtual con `RXD` conectado a RC6 y `TXD` a RC7 (9600 baudios, 8 bits, sin paridad, 1 bit de stop).
3. Cargar el `.hex` en el PIC (frecuencia de 4 MHz) y ejecutar la simulación. La terminal se abre desde **Debug → Virtual Terminal**.
4. Para enviar comandos, hacer clic en la ventana de la terminal y escribir en **mayúsculas**.

### Prueba con la interfaz Ariadna
 
Para probar con la interfaz en vez de la Terminal Virtual hace falta un par de puertos serie virtuales (por ejemplo, Virtual Serial Ports Kit, con el par COM2 ↔ COM3): Proteus usa un puerto del par y la interfaz el otro.
 
1. En Proteus, **reemplazar** la conexión al Terminal Virtual con  **COMPIM** 
2. Conectar los cables **cruzados respecto de lo que sugieren los nombres de los pines**: `TXD` del COMPIM a **RC6** (TX del PIC) y `RXD` del COMPIM a **RC7** (RX del PIC). 
3. Ejecutar la simulación en Proteus **primero** 
4. En `ariadna_gui.py`, verificar que `PORT` sea el otro puerto del par (`COM3`) y ejecutar `python ariadna_gui.py`. Presionar **CONECTAR**.
5. Verificar:
   | Prueba | Resultado esperado |
   |--------|--------------------|
   | Esperar 1–2 s | El valor (`000`) aparece en "Datos de Teseo" y el gráfico se actualiza cada segundo |
   | Mantener **W** | Se enciende RD2 y aparece "Ariadna está guiando a Teseo ▲ adelante" |
   | Soltar **W** | RD2 se apaga a los 200–300 ms (timeout) |
   | Mantener **S** | Se enciende RD3 y aparece el mensaje con ▼ |
   | **A** / **D** | La interfaz los muestra, pero el PIC los ignora (pendiente) |
   | Cambiar de ventana (Alt+Tab) con una tecla presionada | La interfaz deja de enviar y el LED se apaga |
Si la interfaz no recibe datos, se puede comprobar el enlace sin ella con la simulación corriendo y la interfaz cerrada: `py -c "import serial; s=serial.Serial('COM3',9600,timeout=10); print(s.read(10))"` debería imprimir los bytes recibidos.
 
## Integración con el firmware final
 
| Módulo | Qué tiene que hacer |
|--------|---------------------|
| ADC | Dejar el valor de cada sensor en tres variables en BCD desempaquetado (centena, decena y unidad, de 0 a 9). Nombres actuales: `VALUE_CEN_SENSOR1`, `VALUE_DEC_SENSOR1` y `VALUE_UNI_SENSOR1`, a acordar. |
| Motores | Reemplazar el encendido de los LEDs por las rutinas de movimiento, según `ESTADO_MOVIMIENTO`. |
| Interfaz | Ya repite el comando de la tecla mantenida cada 100 ms y grafica el dato recibido (hecho en `ariadna_gui.py`). Falta adaptar el rango del gráfico al valor real del sensor. |
| Todos | El Timer0 y la rutina de interrupción son únicos: si otro módulo necesita su propia base de tiempo, hay que repartir el mismo contador. |
 
## A definir
 
- [ ] Comandos `A` y `D` en el PIC
- [ ] Segundo sensor en la transmisión (y si se agrega un identificador)
- [ ] Qué representa el valor transmitido (unidad y rango)

