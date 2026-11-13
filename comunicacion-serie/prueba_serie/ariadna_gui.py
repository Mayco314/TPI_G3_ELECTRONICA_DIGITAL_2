#===================================================================================================================
# @file         ariadna_gui.py
#
# @brief        Ariadna: interfaz de comunicación con Teseo (robot).
#
# @details      - Recibe por el puerto serie los datos que transmite el PIC (texto ASCII, un valor por línea),
#                 los muestra como número y los grafica en tiempo real.
#               - Envía al PIC los comandos de movimiento (W, A, S, D) mientras la tecla se mantiene
#                 presionada. Los repite cada 100 ms con un temporizador propio, sin depender de la
#                 repetición automática del teclado. Al soltar la tecla deja de enviar y el PIC frena por
#                 timeout (300 ms sin recibir un comando válido).
#               - Adaptado de plotter_serial.py (Ing. E. Migliore).
#
# @author       G3 - Grupo Bomb-bit
# @version      1.0
#
# @note         Requisitos: Python 3 con las librerías pyserial y matplotlib (tkinter viene con Python).
#               Ejecución: py ariadna_gui.py  (o el botón Play de VS Code).
#===================================================================================================================

#===================================================================================================================
# IMPORTACIÓN DE LIBRERÍAS Y MÓDULOS
#===================================================================================================================
import queue                    # Cola segura para pasar datos del hilo de lectura a la ventana
import re                       # Expresiones regulares para extraer el número de cada línea recibida
import threading                # Hilo paralelo para leer el puerto sin trabar la ventana
import time                     # Medición de tiempos (solo para la depuración)
import tkinter as tk            # Interfaz gráfica

import serial                   # Comunicación con el puerto serie (pyserial)
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg   # Gráfico embebido en Tkinter
from matplotlib.figure import Figure                              # Figura de Matplotlib
from matplotlib.ticker import MaxNLocator                         # Ejes con números enteros

#===================================================================================================================
# CONFIGURACIÓN GLOBAL
#===================================================================================================================
PORT = "COM3"               # Puerto COM (en la simulación, el del par virtual conectado a Proteus)
BAUD_RATE = 9600            # Velocidad: debe coincidir con la EUSART del PIC

SEND_PERIOD_MS = 100        # Período de repetición del comando mientras la tecla está presionada
RELEASE_DEBOUNCE_MS = 40    # Filtro de "soltar" falsos (algunos sistemas generan soltar/presionar al repetir)
WINDOW_SAMPLES = 30         # Cantidad de muestras visibles en el gráfico
Y_MIN, Y_MAX = 0, 255       # Rango esperado del dato (8 bits del ADC); el eje crece si llega un valor mayor
DEBUG_SEND = False          # True: imprime en consola cada envío y el tiempo entre envíos

# Teclas válidas: tecla -> (símbolo, descripción del movimiento)
VALID_KEYS = {
    "W": ("▲", "adelante"),
    "A": ("◀", "a la izquierda"),
    "S": ("▼", "atrás"),
    "D": ("▶", "a la derecha"),
}

# Paleta: mar Egeo, oro y el hilo rojo de Ariadna
COLOR_BG = "#14213D"        # Azul egeo oscuro (fondo)
COLOR_PANEL = "#1F3158"     # Azul de los paneles
COLOR_TEXT = "#F5EBD7"      # Crema
COLOR_MUTED = "#9AA7C0"     # Gris azulado
COLOR_GOLD = "#E0B04A"      # Dorado
COLOR_THREAD = "#E4572E"    # Rojo del hilo
COLOR_OK = "#7BC47F"        # Verde de conexión


class Ariadna:
    def __init__(self, root):
        self.root = root
        self.root.title("Ariadna - Interfaz de comunicación con Teseo")
        self.root.geometry("900x640")
        self.root.minsize(760, 560)
        self.root.configure(bg=COLOR_BG)

        # Vinculación del cierre de la ventana con el apagado limpio
        self.root.protocol("WM_DELETE_WINDOW", self.on_closing)

        #===========================================================================================================
        # VARIABLES DE ESTADO Y ESTRUCTURAS DE MEMORIA
        #===========================================================================================================
        self.ser = None                 # Puerto serie
        self.is_running = False         # Conectado y leyendo
        self.is_paused = False          # Gráfico congelado (se sigue leyendo, pero no se actualiza)
        self.rx_queue = queue.Queue()   # Valores recibidos, del hilo de lectura a la ventana
        self.time_data = []             # Eje X (tiempo)
        self.value_data = []            # Eje Y (valores)
        self.current_seconds = 0        # Contador de muestras (1 muestra por segundo)
        self.total_samples = 0          # Total de lecturas recibidas desde que se conectó
        self.held_keys = []             # Teclas válidas mantenidas, en orden de llegada
        self.release_jobs = {}          # "Soltar" pendientes de confirmar (filtro)
        self.last_send = None           # Instante del último envío (solo depuración)

        #===========================================================================================================
        # INTERFAZ GRÁFICA
        #===========================================================================================================
        self.build_header()
        self.build_controls()
        self.build_guidance()
        self.build_body()
        self.set_state("● Desconectado", COLOR_MUTED)
        self.update_guidance()

        # Eventos de teclado y de foco
        self.root.bind("<KeyPress>", self.on_key_press)
        self.root.bind("<KeyRelease>", self.on_key_release)
        self.root.bind("<FocusOut>", self.on_focus_out)

        # Lazos periódicos: envío de comandos y lectura de la cola de datos
        self.send_job = self.root.after(SEND_PERIOD_MS, self.send_loop)
        self.poll_job = self.root.after(50, self.poll_queue)

    #===================================================================================================================
    # CONSTRUCCIÓN DE LA INTERFAZ
    #===================================================================================================================
    def build_header(self):
        tk.Label(
            self.root, text="Ariadna: interfaz de comunicación con Teseo (robot)",
            font=("Georgia", 20, "bold"), bg=COLOR_BG, fg=COLOR_GOLD
        ).pack(side=tk.TOP, pady=(14, 0))
        tk.Label(
            self.root, text="Mantené presionada W, A, S o D para guiar a Teseo",
            font=("Georgia", 11, "italic"), bg=COLOR_BG, fg=COLOR_MUTED
        ).pack(side=tk.TOP, pady=(0, 8))
        # El hilo de Ariadna
        tk.Frame(self.root, height=3, bg=COLOR_THREAD).pack(side=tk.TOP, fill=tk.X, padx=16, pady=(0, 10))

    def build_controls(self):
        frame = tk.Frame(self.root, bg=COLOR_BG)
        frame.pack(side=tk.TOP, fill=tk.X, padx=16, pady=(0, 10))

        def boton(texto, color, comando):
            # takefocus=0: los botones no roban el foco del teclado
            b = tk.Button(
                frame, text=texto, bg=color, fg="white", activebackground=color, activeforeground="white",
                font=("Segoe UI", 10, "bold"), relief="flat", padx=16, pady=5, takefocus=0, command=comando
            )
            b.pack(side=tk.LEFT, padx=(0, 10))

        boton("CONECTAR", "#2E7D32", self.start)
        boton("PAUSAR", "#EF8A17", self.pause)
        boton("SALIR", "#B3261E", self.on_closing)

        tk.Label(
            frame, text=f"Puerto: {PORT}  ·  {BAUD_RATE} baudios",
            font=("Segoe UI", 10, "bold"), bg=COLOR_PANEL, fg=COLOR_TEXT, padx=10, pady=4
        ).pack(side=tk.LEFT, padx=(10, 10))

        self.lbl_state = tk.Label(frame, text="", font=("Segoe UI", 10, "bold"), bg=COLOR_BG, fg=COLOR_MUTED)
        self.lbl_state.pack(side=tk.LEFT)

    def build_guidance(self):
        # Mensaje inferior: indica si Ariadna está guiando a Teseo
        self.lbl_guide = tk.Label(
            self.root, text="", font=("Georgia", 15, "italic"), bg=COLOR_PANEL, fg=COLOR_MUTED, pady=12
        )
        self.lbl_guide.pack(side=tk.BOTTOM, fill=tk.X, padx=16, pady=(0, 14))

    def build_body(self):
        body = tk.Frame(self.root, bg=COLOR_BG)
        body.pack(side=tk.TOP, fill=tk.BOTH, expand=True, padx=16, pady=(0, 10))
        body.columnconfigure(1, weight=1)
        body.rowconfigure(0, weight=1)

        # ---- Panel "Datos de Teseo": valor numérico recibido ----
        panel_data = tk.LabelFrame(
            body, text=" Datos de Teseo ", font=("Georgia", 13, "bold"),
            bg=COLOR_PANEL, fg=COLOR_GOLD, bd=2, relief="groove", padx=18, pady=10
        )
        panel_data.grid(row=0, column=0, sticky="ns", padx=(0, 12))
        tk.Label(panel_data, text="Último valor recibido", font=("Segoe UI", 10),
                 bg=COLOR_PANEL, fg=COLOR_MUTED).pack(pady=(14, 0))
        self.lbl_value = tk.Label(panel_data, text="---", font=("Consolas", 54, "bold"),
                                  bg=COLOR_PANEL, fg=COLOR_TEXT)
        self.lbl_value.pack(padx=10, pady=(0, 14))
        self.lbl_samples = tk.Label(panel_data, text="Lecturas recibidas: 0", font=("Segoe UI", 10),
                                    bg=COLOR_PANEL, fg=COLOR_MUTED)
        self.lbl_samples.pack(pady=(0, 10))

        # ---- Panel del gráfico ----
        panel_graph = tk.Frame(body, bg=COLOR_PANEL, bd=2, relief="groove")
        panel_graph.grid(row=0, column=1, sticky="nsew")

        self.fig = Figure(figsize=(6, 4), dpi=100, facecolor=COLOR_PANEL)
        self.ax = self.fig.add_subplot(111)
        self.ax.set_facecolor(COLOR_BG)
        self.ax.set_title("Historial del dato recibido", color=COLOR_GOLD, fontfamily="serif", fontsize=13)
        self.ax.set_xlabel("Tiempo (segundos)", color=COLOR_TEXT)
        self.ax.set_ylabel("Valor", color=COLOR_TEXT)
        self.ax.tick_params(colors=COLOR_MUTED)
        for spine in self.ax.spines.values():
            spine.set_color(COLOR_MUTED)
        self.ax.xaxis.set_major_locator(MaxNLocator(integer=True))     # Eje X con enteros
        self.ax.set_ylim(Y_MIN - 5, Y_MAX + 5)
        self.ax.grid(True, color="#3A4D7A", linewidth=0.8)
        self.line, = self.ax.plot([], [], color=COLOR_THREAD, linewidth=2.5, marker="o", markersize=4)
        self.fig.tight_layout()

        self.canvas = FigureCanvasTkAgg(self.fig, master=panel_graph)
        self.canvas.get_tk_widget().pack(fill=tk.BOTH, expand=True)

    #===================================================================================================================
    # CONTROL DE LA CONEXIÓN
    #===================================================================================================================
    #*******************************************************************************************************************
    # @brief Abre el puerto y lanza el hilo de lectura. Si estaba pausado, reanuda.
    #*******************************************************************************************************************
    def start(self):
        if self.is_paused:
            self.is_paused = False
            self.set_state("● Conectado", COLOR_OK)
            return
        if self.is_running:
            return
        try:
            self.ser = serial.Serial(PORT, BAUD_RATE, timeout=1, write_timeout=0.5)
        except Exception as e:
            print(f"No se pudo abrir {PORT}: {e}")
            self.ser = None
            self.set_state(f"● No se pudo abrir {PORT}", COLOR_THREAD)
            return

        self.rx_queue = queue.Queue()
        self.clear_data()
        self.is_running = True
        self.is_paused = False
        self.set_state("● Conectado", COLOR_OK)
        self.update_guidance()
        threading.Thread(target=self.read_serial, daemon=True).start()

    #*******************************************************************************************************************
    # @brief Congela el gráfico y el valor mostrado. El puerto sigue abierto y los comandos se siguen enviando.
    #*******************************************************************************************************************
    def pause(self):
        if self.is_running:
            self.is_paused = True
            self.set_state("● Pausado", COLOR_GOLD)

    #*******************************************************************************************************************
    # @brief Cierre seguro: cancela los temporizadores, libera el puerto y destruye la ventana.
    #*******************************************************************************************************************
    def on_closing(self):
        self.is_running = False
        self.is_paused = False
        for job in (self.send_job, self.poll_job):
            self.root.after_cancel(job)
        for job in self.release_jobs.values():
            self.root.after_cancel(job)
        if self.ser is not None and self.ser.is_open:
            self.ser.close()
        self.root.quit()
        self.root.destroy()

    def connection_lost(self):
        self.is_running = False
        if self.ser is not None:
            try:
                self.ser.close()
            except Exception:
                pass
        self.ser = None
        self.release_all()
        self.set_state("● Conexión perdida", COLOR_THREAD)
        self.update_guidance()

    #===================================================================================================================
    # RECEPCIÓN (PIC -> PC)
    #===================================================================================================================
    #*******************************************************************************************************************
    # @brief Hilo de fondo: lee líneas del puerto y deja los valores en la cola.
    # @details Cada línea del PIC tiene el formato "123\r\n". Se extrae el primer número entero de la línea.
    #*******************************************************************************************************************
    def read_serial(self):
        while self.is_running:
            try:
                raw = self.ser.readline().decode("utf-8", errors="ignore").strip()
            except Exception:
                if self.is_running:
                    self.rx_queue.put(None)     # Aviso de conexión perdida
                break
            numeros = re.findall(r"\d+", raw)
            if numeros:
                self.rx_queue.put(int(numeros[0]))

    #*******************************************************************************************************************
    # @brief Lazo en la ventana principal: vuelca a la pantalla lo que dejó el hilo de lectura.
    #*******************************************************************************************************************
    def poll_queue(self):
        try:
            while True:
                item = self.rx_queue.get_nowait()
                if item is None:
                    self.connection_lost()
                elif not self.is_paused:
                    self.add_sample(item)
        except queue.Empty:
            pass
        self.poll_job = self.root.after(50, self.poll_queue)

    def add_sample(self, valor):
        self.time_data.append(self.current_seconds)
        self.value_data.append(valor)
        self.current_seconds += 1               # 1 muestra por segundo (período de transmisión del PIC)
        self.total_samples += 1
        if len(self.time_data) > WINDOW_SAMPLES:    # Ventana móvil
            self.time_data.pop(0)
            self.value_data.pop(0)
        self.lbl_value.config(text=f"{valor:03d}")
        self.lbl_samples.config(text=f"Lecturas recibidas: {self.total_samples}")
        self.update_plot()

    def update_plot(self):
        self.line.set_data(self.time_data, self.value_data)
        self.ax.set_xlim(min(self.time_data), max(self.time_data) + 1)
        self.ax.set_ylim(Y_MIN - 5, max(Y_MAX, max(self.value_data)) + 5)
        self.canvas.draw_idle()

    def clear_data(self):
        self.time_data.clear()
        self.value_data.clear()
        self.current_seconds = 0
        self.total_samples = 0
        self.line.set_data([], [])
        self.canvas.draw_idle()
        self.lbl_value.config(text="---")
        self.lbl_samples.config(text="Lecturas recibidas: 0")

    #===================================================================================================================
    # ENVÍO DE COMANDOS (PC -> PIC)
    #===================================================================================================================
    #*******************************************************************************************************************
    # @brief Al presionar una tecla válida la registra como mantenida y envía su comando de inmediato.
    # @details La repetición automática del teclado se ignora: el reenvío lo hace send_loop cada 100 ms.
    #*******************************************************************************************************************
    def on_key_press(self, event):
        key = event.keysym.upper()
        if key not in VALID_KEYS:
            return
        # Si había un "soltar" pendiente, era una repetición automática: la tecla sigue presionada
        job = self.release_jobs.pop(key, None)
        if job is not None:
            self.root.after_cancel(job)
            return
        if key not in self.held_keys:
            self.held_keys.append(key)
            self.update_guidance()
            # Envío inmediato y reinicio del lazo de 100 ms
            self.root.after_cancel(self.send_job)
            self.send_loop()

    #*******************************************************************************************************************
    # @brief Al soltar, espera unos ms para confirmar que no fue una falsa liberación.
    #*******************************************************************************************************************
    def on_key_release(self, event):
        key = event.keysym.upper()
        if key in self.held_keys and key not in self.release_jobs:
            self.release_jobs[key] = self.root.after(
                RELEASE_DEBOUNCE_MS, lambda k=key: self.confirm_release(k)
            )

    def confirm_release(self, key):
        self.release_jobs.pop(key, None)
        if key in self.held_keys:
            self.held_keys.remove(key)
        self.update_guidance()

    #*******************************************************************************************************************
    # @brief Si la ventana pierde el foco con una tecla apretada, no llegará el "soltar": se liberan todas.
    #*******************************************************************************************************************
    def on_focus_out(self, event):
        self.root.after(50, self.check_focus)

    def check_focus(self):
        if self.root.focus_displayof() is None:     # Ningún widget de la aplicación tiene el foco
            self.release_all()
            self.update_guidance()

    def release_all(self):
        self.held_keys.clear()
        for job in self.release_jobs.values():
            self.root.after_cancel(job)
        self.release_jobs.clear()

    #*******************************************************************************************************************
    # @brief Cada 100 ms envía al PIC el comando de la última tecla presionada que siga mantenida.
    # @details Si no hay tecla mantenida no envía nada: el PIC frena solo al cumplirse el timeout.
    #*******************************************************************************************************************
    def send_loop(self):
        if self.held_keys and self.is_running and self.ser is not None and self.ser.is_open:
            key = self.held_keys[-1]
            try:
                self.ser.write(key.encode("ascii"))
                if DEBUG_SEND:
                    ahora = time.perf_counter()
                    dt = "" if self.last_send is None else f"  (+{(ahora - self.last_send) * 1000:.0f} ms)"
                    print(f"Envío '{key}'{dt}")
                    self.last_send = ahora
            except Exception as e:
                print(f"Error al enviar: {e}")
        self.send_job = self.root.after(SEND_PERIOD_MS, self.send_loop)

    #===================================================================================================================
    # MENSAJES EN PANTALLA
    #===================================================================================================================
    def set_state(self, texto, color):
        self.lbl_state.config(text=texto, fg=color)

    def update_guidance(self):
        if not self.is_running:
            self.lbl_guide.config(text="Presioná CONECTAR para que Ariadna pueda guiar a Teseo", fg=COLOR_MUTED)
        elif self.held_keys:
            simbolo, accion = VALID_KEYS[self.held_keys[-1]]
            self.lbl_guide.config(text=f"Ariadna está guiando a Teseo   {simbolo} {accion}", fg=COLOR_GOLD)
        else:
            self.lbl_guide.config(text="Teseo espera la guía de Ariadna", fg=COLOR_MUTED)
            self.last_send = None


#===================================================================================================================
# ENTRADA PRINCIPAL DEL PROGRAMA (MAIN)
#===================================================================================================================
if __name__ == "__main__":
    root = tk.Tk()
    app = Ariadna(root)
    root.mainloop()
