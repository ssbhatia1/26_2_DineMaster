#pragma once

#if defined(__has_include)
  #if __has_include("../gtk/gtk.h")
    #include "../gtk/gtk.h"
  #elif __has_include(<gtk/gtk.h>)
    #include <gtk/gtk.h>
  #endif
#else
  #include "../gtk/gtk.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct _FlView FlView;
typedef struct _FlDartProject FlDartProject;
typedef struct _FlPluginRegistry FlPluginRegistry;

#define FL_PLUGIN_REGISTRY(obj) ((FlPluginRegistry*)(obj))

FlView* fl_view_new(FlDartProject* project);
FlDartProject* fl_dart_project_new(void);
void fl_dart_project_set_dart_entrypoint_arguments(FlDartProject* project, char** argv);
void fl_register_plugins(FlPluginRegistry* registry);
void fl_view_get_background_color(FlView* view, GdkRGBA* color);
void fl_view_set_background_color(FlView* view, const GdkRGBA* color);

#ifdef __cplusplus
}
#endif
