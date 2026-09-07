#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void* gpointer;
typedef int gboolean;
typedef char gchar;
#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

typedef size_t GType;

typedef struct _GError {
  int domain;
  int code;
  gchar* message;
} GError;

typedef struct _GdkRGBA {
  double red;
  double green;
  double blue;
  double alpha;
} GdkRGBA;

typedef struct _GObject GObject;
typedef struct _GObjectClass {
  void (*dispose)(GObject* object);
} GObjectClass;

struct _GObject {
  int dummy;
};

typedef struct _GApplication GApplication;
typedef struct _GApplicationClass {
  void (*activate)(GApplication* application);
  void (*startup)(GApplication* application);
  void (*shutdown)(GApplication* application);
  gboolean (*local_command_line)(GApplication* application, gchar*** arguments, int* exit_status);
} GApplicationClass;

struct _GApplication {
  GObject parent_instance;
};

typedef struct _GtkApplication GtkApplication;
typedef struct _GtkApplicationClass {
  GApplicationClass parent_class;
} GtkApplicationClass;

struct _GtkApplication {
  GApplication parent_instance;
};

typedef struct _GtkWidget GtkWidget;
typedef struct _GtkWindow GtkWindow;
typedef struct _GtkHeaderBar GtkHeaderBar;
typedef struct _GtkContainer GtkContainer;

#define G_DECLARE_FINAL_TYPE(ModuleObjName, module_obj_name, MODULE, OBJ_NAME, ParentName) \
  typedef struct _##ModuleObjName ModuleObjName; \
  typedef struct _##ModuleObjName##Class { ParentName##Class parent_class; } ModuleObjName##Class; \
  GType module_obj_name##_get_type(void);

#define G_DEFINE_TYPE(TN, t_n, T_P) \
  static void t_n##_init(TN* self); \
  static void t_n##_class_init(TN##Class* klass); \
  static GApplicationClass* t_n##_parent_class = (GApplicationClass*)0;

#define GTK_HEADER_BAR(obj) ((GtkHeaderBar*)(obj))
#define GTK_WINDOW(obj) ((GtkWindow*)(obj))
#define GTK_WIDGET(obj) ((GtkWidget*)(obj))
#define GTK_APPLICATION(obj) ((GtkApplication*)(obj))
#define MY_APPLICATION(obj) ((MyApplication*)(obj))
#define GTK_CONTAINER(obj) ((GtkContainer*)(obj))
#define G_APPLICATION(obj) ((GApplication*)(obj))
#define G_APPLICATION_CLASS(klass) ((GApplicationClass*)(klass))
#define G_OBJECT_CLASS(klass) ((GObjectClass*)(klass))
#define GTK_TYPE_APPLICATION ((GType)0)
#define G_CALLBACK(f) ((void*)(f))

#define G_APPLICATION_NON_UNIQUE 0
#define APPLICATION_ID "com.dinemaster"

#define g_autoptr(TypeName) TypeName*
#define g_clear_object(ptr) do {} while(0)
#define g_clear_pointer(pp, destroy) do { if (*(pp)) { (destroy)(*(pp)); *(pp) = NULL; } } while(0)
#define g_signal_connect_swapped(instance, detailed_signal, c_handler, data) (0)
#define g_warning(...) do {} while(0)

GType gtk_application_get_type(void);
GtkHeaderBar* gtk_header_bar_new(void);
void gtk_widget_show(GtkWidget* widget);
void gtk_header_bar_set_title(GtkHeaderBar* bar, const gchar* title);
void gtk_header_bar_set_show_close_button(GtkHeaderBar* bar, gboolean setting);
void gtk_window_set_titlebar(GtkWindow* window, GtkWidget* titlebar);
void gtk_window_set_title(GtkWindow* window, const gchar* title);
void gtk_window_set_default_size(GtkWindow* window, int width, int height);
GtkWidget* gtk_widget_get_toplevel(GtkWidget* widget);
GtkWidget* gtk_application_window_new(GtkApplication* application);
void gtk_widget_realize(GtkWidget* widget);
void gtk_widget_grab_focus(GtkWidget* widget);
void gtk_container_add(GtkContainer* container, GtkWidget* widget);

int g_strcmp0(const char* str1, const char* str2);
const char* g_getenv(const char* variable);
gchar** g_strdupv(gchar** str_array);
void g_strfreev(gchar** str_array);
gboolean g_application_activate(GApplication* application);
gboolean g_application_register(GApplication* application, void* cancellable, GError** error);
gboolean gdk_rgba_parse(GdkRGBA* rgba, const char* spec);
gpointer g_object_new(GType type, const char* first_prop_name, ...);
void g_set_prgname(const char* prgname);

#ifdef __cplusplus
}
#endif
