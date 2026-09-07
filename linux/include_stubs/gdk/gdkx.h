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
