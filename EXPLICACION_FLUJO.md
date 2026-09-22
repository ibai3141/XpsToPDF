# Flujo XPS → PDF

## Objetivo

El sistema automatiza este flujo:

```text
Aplicación de impresión
    ↓
Microsoft XPS Document Writer
    ↓
SaveAs Interceptor (AutoHotkey)
    ↓
C:\XPS_OUT\NombreDelDocumento.xps
    ↓
XpsToPdfService
    ↓
GhostXPS
    ↓
C:\PDF\NombreDelDocumento.pdf
```

## 1. Interceptor AutoHotkey

Archivo:

```text
SaveAsInterceptor\saveas_xps.ahk
```

El interceptor se ejecuta en la sesión interactiva del usuario. Un servicio de
Windows no puede controlar directamente una ventana del escritorio, por eso
esta parte debe ejecutarse como proceso de usuario.

### Captura del nombre

Antes de imprimir, el script guarda el título de la aplicación activa. Puede
ser LibreOffice, Tytan u otra aplicación.

Ejemplos:

```text
Zadanie_skrót_21_września.docx — LibreOffice Writer
Kartoteka wpłat
```

Si XPS Writer propone un nombre genérico como `Printing` o `Drukowanie
dokumentu`, el script utiliza el título capturado de la aplicación.

### Limpieza del nombre

El script elimina la extensión original y los sufijos de la aplicación:

```text
Zadanie_skrót_21_września.docx — LibreOffice Writer
```

se transforma en:

```text
Zadanie_skrót_21_września
```

The interceptor keeps the detected document name generic; it does not contain
hard-coded rules for one particular report or application.

### Selección del formato

Microsoft XPS Document Writer puede seleccionar por defecto OpenXPS:

```text
OpenXPS (*.oxps)
```

El script intenta seleccionar explícitamente:

```text
XPS Document (*.xps)
```

También escribe el nombre en el campo de archivo y pulsa Enter para confirmar
el guardado. La ventana se vuelve transparente para que el usuario no tenga
que interactuar con ella.

## 2. Servicio XpsToPdfService

Archivo principal:

```text
Worker.cs
```

### Vigilancia de archivos

El servicio observa:

```text
C:\XPS_OUT
```

Acepta tanto archivos `.xps` como `.oxps`.

### Espera del archivo completo

El evento `Created` puede llegar mientras Windows todavía está escribiendo el
archivo. Antes de convertirlo, el servicio comprueba que:

1. El archivo existe.
2. No está vacío.
3. Puede abrirse en modo exclusivo.
4. Su tamaño y fecha permanecen estables durante varias comprobaciones.

Esto evita convertir paquetes XPS incompletos.

### Conversión

El servicio ejecuta:

```text
gxpswin64.exe
```

GhostXPS es el intérprete adecuado para XPS/OpenXPS. Se utiliza el dispositivo
`pdfwrite` para crear el PDF.

La salida se crea primero como archivo temporal:

```text
Nombre.tmp.pdf
```

Solo cuando GhostXPS termina con código `0` se renombra a:

```text
Nombre.pdf
```

## 3. Problemas que se corrigieron

### Ejecutable incorrecto

Se utilizaba `gswin64c.exe` para leer XPS. El ejecutable correcto es
`gxpswin64.exe`.

### Archivo incompleto

Una espera fija de dos segundos no garantizaba que el XPS hubiera terminado de
escribirse. Se implementó una comprobación de estabilidad del archivo.

### Extensión `.oxps`

El servicio solo vigilaba `*.xps`, pero el controlador podía generar `*.oxps`.
Ahora acepta ambos formatos.

### Nombre repetido o corrupto

El temporizador podía procesar varias veces la misma ventana y añadir varias
extensiones `.xps`. También se llegó a reutilizar contenido antiguo del
portapapeles, produciendo nombres como `av.oxps`.

Ahora cada diálogo se procesa una sola vez y la ruta se escribe directamente
en el control de nombre.

### Ventana bloqueada

Ocultar completamente la ventana con `WinHide` hacía que AutoHotkey perdiera
acceso a sus controles. Se sustituyó por transparencia y se utiliza Enter como
acción predeterminada de Guardar, en lugar de asumir que `Button1` siempre es el
botón correcto.

### Varias instancias del servicio

Ejecutar varias instancias bloqueaba el ejecutable durante la compilación. Solo
debe ejecutarse una instancia de `XpsToPdfService`.

## 4. Limitación actual

El proyecto no contiene el código fuente de la aplicación Tytan que llama a
`PrintDocument.Print()`. Por eso no se puede modificar directamente esta línea:

```csharp
pd.DocumentName = filename;
pd.Print();
```

La solución actual obtiene el nombre desde el título de la ventana y aplica
únicamente la limpieza genérica necesaria para un nombre de archivo Windows.

### Código equivalente a `DocumentName`

Como no disponemos del código de Tytan, el interceptor captura la ventana activa
antes de imprimir:

```autohotkey
activeHwnd := WinExist("A")
activeTitle := Trim(WinGetTitle("ahk_id " activeHwnd))

if (activeTitle != "" && !IsGenericPrintJobName(activeTitle))
    lastDocumentTitle := activeTitle
```

Cuando aparece el diálogo de XPS, utiliza ese título para crear la ruta:

```autohotkey
if (documentName = "" || IsGenericPrintJobName(documentName))
    documentName := lastDocumentTitle

documentName := RegExReplace(documentName, "\s+[—-]\s+.*$")
documentName := RegExReplace(
    documentName,
    "i)\.(?:docx|doc|odt|rtf|txt|xlsx|xls|ods|pptx|ppt|odp|pdf)$"
)

filePath := xpsFolder . "\" . documentName . ".xps"
```

Después escribe la ruta y confirma el cuadro:

```autohotkey
ControlSetText filePath, "Edit1", "ahk_id " hwnd
WinSetTransparent 0, "ahk_id " hwnd
ControlSend "{Enter}", , "ahk_id " hwnd
```

El servicio también acepta ambas extensiones:

```csharp
if (!e.FullPath.EndsWith(".xps", StringComparison.OrdinalIgnoreCase) &&
    !e.FullPath.EndsWith(".oxps", StringComparison.OrdinalIgnoreCase))
    return;
```

La solución ideal, si se obtiene el código de Tytan, es asignar directamente:

```csharp
pd.DocumentName = filename;
pd.Print();
```

De esa forma Microsoft XPS Document Writer recibiría el nombre correcto desde
el origen, sin necesidad de inferirlo desde el título de la ventana.
