"""
Proyecto : Procesador de imágenes 128x128 con detección de bordes (Sobel / Prewitt)
           en FPGA Basys 3 (xc7a35tcpg236-1)
Archivo  : fpga_gui.py  (interfaz gráfica)
Autor    : Ángel Casique

DECLARACIÓN DE USO DE IA
  Este código fue diseñado y escrito por el autor (Ángel Casique). La IA se usó
  como apoyo de corrección:
    - Gemini (Google): revisó el código que el autor iba escribiendo.
    - Claude (Anthropic): revisión final, corrección de errores y mejora del
      aspecto visual de la interfaz original del autor.

Uso:   python fpga_gui.py      (necesita fpga_core.py en la misma carpeta)
  - El filtro REAL lo elige el switch SW0 de la Basys 3 (abajo = Sobel, arriba =
    Prewitt). El selector de la interfaz solo le dice al programa cuál es, para
    calcular la referencia en software y comparar.
  - "Simular FPGA" permite probar la interfaz sin la placa conectada.
"""
import queue
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

import numpy as np
from PIL import Image, ImageTk

import fpga_core as core

# Paleta
BG, PANEL, FG = "#0f172a", "#1e293b", "#e2e8f0"
MUTED, ACCENT, OK, BAD = "#94a3b8", "#22d3ee", "#4ade80", "#f87171"
VISOR = 256                      # tamaño en pantalla de cada imagen


def a_foto(arr):
    """Matriz uint8 -> imagen de pantalla (se amplía sin suavizar para ver los píxeles)."""
    return ImageTk.PhotoImage(Image.fromarray(arr).resize((VISOR, VISOR), core.NEAREST))


class App:
    def __init__(self, root):
        self.root = root
        root.title("FPGA · Detección de bordes Sobel / Prewitt")
        root.geometry("1010x640")
        root.configure(bg=BG)
        root.minsize(980, 600)

        self.img_tx = None            # imagen original 128x128
        self.img_rx = None            # resultado de la FPGA 128x128
        self.cola = queue.Queue()     # mensajes del hilo de trabajo
        self.puertos = {}

        self._estilos()
        self._construir()
        self.refrescar_puertos()
        self.root.after(50, self._revisar_cola)

    # ------------------------------------------------------------------ estilos
    def _estilos(self):
        st = ttk.Style()
        st.theme_use("clam")
        st.configure(".", background=BG, foreground=FG, fieldbackground=PANEL,
                     font=("Segoe UI", 10))
        st.configure("Card.TFrame", background=PANEL)
        st.configure("Card.TLabel", background=PANEL, foreground=FG)
        st.configure("Muted.TLabel", background=PANEL, foreground=MUTED, font=("Segoe UI", 9))
        st.configure("Title.TLabel", background=BG, foreground=ACCENT, font=("Segoe UI", 18, "bold"))
        st.configure("Sub.TLabel", background=BG, foreground=MUTED, font=("Segoe UI", 10))
        st.configure("Head.TLabel", background=PANEL, foreground=ACCENT, font=("Segoe UI", 11, "bold"))
        st.configure("TButton", background="#334155", foreground=FG, padding=7, borderwidth=0)
        st.map("TButton", background=[("active", "#475569"), ("disabled", "#1e293b")],
               foreground=[("disabled", "#64748b")])
        st.configure("Accent.TButton", background=ACCENT, foreground="#0f172a",
                     font=("Segoe UI", 11, "bold"), padding=10)
        st.map("Accent.TButton", background=[("active", "#67e8f9"), ("disabled", "#334155")],
               foreground=[("disabled", "#64748b")])
        st.configure("TRadiobutton", background=PANEL, foreground=FG)
        st.map("TRadiobutton", background=[("active", PANEL)])
        st.configure("TCheckbutton", background=PANEL, foreground=FG)
        st.map("TCheckbutton", background=[("active", PANEL)])
        st.configure("TCombobox", fieldbackground="#0f172a", background="#334155",
                     foreground=FG, arrowcolor=FG)
        st.configure("Horizontal.TProgressbar", troughcolor=BG, background=ACCENT, thickness=10)

    # --------------------------------------------------------------- construcción
    def _construir(self):
        cab = ttk.Frame(self.root)
        cab.pack(fill=tk.X, padx=20, pady=(14, 6))
        ttk.Label(cab, text="Detección de bordes en FPGA", style="Title.TLabel").pack(anchor="w")
        ttk.Label(cab, text="Basys 3 · Sobel / Prewitt · UART 115200 baudios · imagen 128×128",
                  style="Sub.TLabel").pack(anchor="w")

        cuerpo = ttk.Frame(self.root)
        cuerpo.pack(fill=tk.BOTH, expand=True, padx=20, pady=8)

        # ----- Panel de control (izquierda)
        ctl = ttk.Frame(cuerpo, style="Card.TFrame", padding=14)
        ctl.pack(side=tk.LEFT, fill=tk.Y, padx=(0, 14))

        ttk.Label(ctl, text="Conexión", style="Head.TLabel").pack(anchor="w")
        fila = ttk.Frame(ctl, style="Card.TFrame")
        fila.pack(fill=tk.X, pady=(6, 2))
        self.combo_port = ttk.Combobox(fila, width=26, state="readonly")
        self.combo_port.pack(side=tk.LEFT)
        ttk.Button(fila, text="↻", width=3, command=self.refrescar_puertos).pack(side=tk.LEFT, padx=(6, 0))
        ttk.Label(ctl, text="La Basys 3 crea 2 puertos; el de UART\nsuele ser el de número mayor.",
                  style="Muted.TLabel").pack(anchor="w", pady=(0, 10))

        ttk.Label(ctl, text="Imagen", style="Head.TLabel").pack(anchor="w", pady=(6, 0))
        ttk.Button(ctl, text="📁  Cargar imagen", command=self.cargar_imagen).pack(fill=tk.X, pady=(6, 2))
        self.lbl_archivo = ttk.Label(ctl, text="Ninguna imagen cargada", style="Muted.TLabel",
                                     wraplength=250)
        self.lbl_archivo.pack(anchor="w", pady=(0, 10))

        ttk.Label(ctl, text="Filtro (switch SW0 de la placa)", style="Head.TLabel").pack(anchor="w", pady=(6, 0))
        self.filtro = tk.StringVar(value="Sobel")
        ttk.Radiobutton(ctl, text="Sobel   ·  SW0 abajo (0)", variable=self.filtro,
                        value="Sobel").pack(anchor="w", pady=(6, 0))
        ttk.Radiobutton(ctl, text="Prewitt  ·  SW0 arriba (1)", variable=self.filtro,
                        value="Prewitt").pack(anchor="w")
        ttk.Label(ctl, text="El filtro lo elige el switch físico.\nEsto solo calcula la referencia.",
                  style="Muted.TLabel").pack(anchor="w", pady=(2, 10))

        self.simular = tk.BooleanVar(value=False)
        ttk.Checkbutton(ctl, text="Simular FPGA (sin placa)", variable=self.simular).pack(anchor="w", pady=(4, 10))

        self.btn_proc = ttk.Button(ctl, text="⚡  Procesar", style="Accent.TButton", command=self.procesar)
        self.btn_proc.pack(fill=tk.X, pady=(4, 6))
        self.btn_guardar = ttk.Button(ctl, text="💾  Guardar resultado", command=self.guardar, state="disabled")
        self.btn_guardar.pack(fill=tk.X)

        self.barra = ttk.Progressbar(ctl, mode="determinate", maximum=100)
        self.barra.pack(fill=tk.X, pady=(14, 4))
        self.lbl_estado = ttk.Label(ctl, text="Esperando imagen…", style="Card.TLabel", wraplength=250)
        self.lbl_estado.pack(anchor="w")
        self.lbl_stats = ttk.Label(ctl, text="", style="Muted.TLabel", wraplength=250, justify="left")
        self.lbl_stats.pack(anchor="w", pady=(6, 0))

        # ----- Visores (derecha)
        vis = ttk.Frame(cuerpo)
        vis.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        vacia = a_foto(np.full((core.M, core.M), 30, dtype=np.uint8))
        self.visores = []
        for col, titulo in enumerate(["Original (128×128)", "Resultado FPGA", "Referencia en software"]):
            tarjeta = ttk.Frame(vis, style="Card.TFrame", padding=8)
            tarjeta.grid(row=0, column=col, padx=6, sticky="n")
            ttk.Label(tarjeta, text=titulo, style="Head.TLabel").pack(pady=(0, 6))
            lbl = ttk.Label(tarjeta, image=vacia, style="Card.TLabel")
            lbl.image = vacia
            lbl.pack()
            self.visores.append(lbl)
        ttk.Label(vis, text="La referencia es el mismo filtro calculado con NumPy; si coincide, el hardware está bien.",
                  style="Sub.TLabel").grid(row=1, column=0, columnspan=3, pady=(10, 0))

    # ------------------------------------------------------------------ acciones
    def _mostrar(self, idx, arr):
        foto = a_foto(arr)
        self.visores[idx].config(image=foto)
        self.visores[idx].image = foto

    def refrescar_puertos(self):
        lista = core.listar_puertos()
        self.puertos = {f"{d} — {desc}": d for d, desc in lista}
        valores = list(self.puertos.keys()) or ["(sin puertos)"]
        self.combo_port["values"] = valores
        self.combo_port.set(valores[-1])

    def cargar_imagen(self):
        ruta = filedialog.askopenfilename(filetypes=[("Imágenes", "*.jpg *.jpeg *.png *.bmp")])
        if not ruta:
            return
        self.img_tx = core.preparar_imagen(ruta)
        self.img_rx = None
        self._mostrar(0, self.img_tx)
        self._mostrar(1, np.full((core.M, core.M), 30, dtype=np.uint8))
        self._mostrar(2, np.full((core.M, core.M), 30, dtype=np.uint8))
        self.lbl_archivo.config(text=ruta.split("/")[-1].split("\\")[-1])
        self.lbl_estado.config(text="Imagen lista. Pulsa Procesar.", foreground=FG)
        self.lbl_stats.config(text="")
        self.barra["value"] = 0
        self.btn_guardar.config(state="disabled")

    def procesar(self):
        if self.img_tx is None:
            messagebox.showwarning("Atención", "Carga una imagen primero.")
            return
        simular = self.simular.get()
        puerto = self.puertos.get(self.combo_port.get())
        if not simular and not puerto:
            messagebox.showwarning("Atención", "No hay puerto serial seleccionado.")
            return
        filtro = self.filtro.get()
        self.btn_proc.config(state="disabled")
        self.btn_guardar.config(state="disabled")
        self.barra["value"] = 0
        self.lbl_estado.config(text="Procesando…", foreground=FG)
        threading.Thread(target=self._trabajo, args=(simular, puerto, filtro), daemon=True).start()

    def _trabajo(self, simular, puerto, filtro):
        """Corre en un hilo para que la ventana no se congele."""
        try:
            ref = core.filtro_referencia(self.img_tx, filtro)
            if simular:
                self.cola.put(("progreso", 1.0))
                self.cola.put(("ok", ref.copy(), ref, 0.0, core.N_SALIDA))
                return
            rx, seg = core.procesar_en_fpga(puerto, self.img_tx,
                                            progreso=lambda f: self.cola.put(("progreso", f)))
            if len(rx) < core.N_SALIDA:
                self.cola.put(("corto", len(rx)))
                return
            self.cola.put(("ok", core.reconstruir(rx), ref, seg, len(rx)))
        except Exception as e:                       # puerto ocupado, no existe, etc.
            self.cola.put(("error", str(e)))

    def _revisar_cola(self):
        try:
            while True:
                msg = self.cola.get_nowait()
                if msg[0] == "progreso":
                    self.barra["value"] = msg[1] * 100
                elif msg[0] == "ok":
                    _, hw, ref, seg, n = msg
                    self.img_rx = hw
                    self._mostrar(1, hw)
                    self._mostrar(2, ref)
                    coincide = float(np.mean(hw == ref) * 100)
                    bien = coincide >= 99.99
                    self.lbl_estado.config(
                        text="✔ Coincide con la referencia" if bien else "⚠ Hay diferencias con la referencia",
                        foreground=OK if bien else BAD)
                    self.lbl_stats.config(
                        text=f"Bytes recibidos: {n} de {core.N_SALIDA}\n"
                             f"Tiempo: {seg:.2f} s\nCoincidencia: {coincide:.2f} %")
                    self.btn_guardar.config(state="normal")
                    self.btn_proc.config(state="normal")
                elif msg[0] == "corto":
                    self.lbl_estado.config(text=f"✖ Llegaron {msg[1]} de {core.N_SALIDA} bytes", foreground=BAD)
                    self.lbl_stats.config(text="Revisa: bitstream cargado, SW0, reset (botón central)\n"
                                               "y que el puerto sea el del UART.")
                    self.btn_proc.config(state="normal")
                elif msg[0] == "error":
                    self.lbl_estado.config(text="✖ Error de comunicación", foreground=BAD)
                    self.lbl_stats.config(text=msg[1])
                    self.btn_proc.config(state="normal")
        except queue.Empty:
            pass
        self.root.after(50, self._revisar_cola)

    def guardar(self):
        if self.img_rx is None:
            return
        ruta = filedialog.asksaveasfilename(defaultextension=".png", filetypes=[("PNG", "*.png")],
                                            initialfile="resultado_fpga.png")
        if ruta:
            Image.fromarray(self.img_rx).save(ruta)
            self.lbl_estado.config(text="Resultado guardado.", foreground=OK)



if __name__ == "__main__":
    root = tk.Tk()
    App(root)
    root.mainloop()
