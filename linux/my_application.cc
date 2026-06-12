#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  gint window_x;
  gint window_y;
  gint window_width;
  gint window_height;
  gboolean window_maximized;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

constexpr gint kDefaultWindowOffset = 100;
constexpr gint kFallbackWindowWidth = 960;
constexpr gint kFallbackWindowHeight = 540;

static void set_default_window_state(MyApplication* self) {
  self->window_x = kDefaultWindowOffset;
  self->window_y = kDefaultWindowOffset;
  self->window_width = kFallbackWindowWidth;
  self->window_height = kFallbackWindowHeight;
  self->window_maximized = FALSE;

  GdkScreen* screen = gdk_screen_get_default();
  if (screen == nullptr || gdk_screen_get_n_monitors(screen) == 0) {
    return;
  }

  GdkRectangle bounds{};
  gdk_screen_get_monitor_geometry(screen, 0, &bounds);
  self->window_x = bounds.x + kDefaultWindowOffset;
  self->window_y = bounds.y + kDefaultWindowOffset;
  self->window_width = bounds.width / 2;
  self->window_height = bounds.height / 2;
}

static gchar* get_window_state_path() {
  return g_build_filename(g_get_user_config_dir(), "loliSnatcher",
                          "window.ini", nullptr);
}

static void load_window_state(MyApplication* self) {
  g_autofree gchar* path = get_window_state_path();
  g_autoptr(GKeyFile) key_file = g_key_file_new();
  g_autoptr(GError) error = nullptr;
  if (!g_key_file_load_from_file(key_file, path, G_KEY_FILE_NONE, &error)) {
    return;
  }

  const gint width = g_key_file_get_integer(key_file, "window", "width", nullptr);
  const gint height =
      g_key_file_get_integer(key_file, "window", "height", nullptr);
  if (width >= 320 && height >= 240) {
    self->window_width = width;
    self->window_height = height;
  }

  self->window_x = g_key_file_get_integer(key_file, "window", "x", nullptr);
  self->window_y = g_key_file_get_integer(key_file, "window", "y", nullptr);
  self->window_maximized =
      g_key_file_get_boolean(key_file, "window", "maximized", nullptr);

  GdkScreen* screen = gdk_screen_get_default();
  if (screen == nullptr) {
    return;
  }

  GdkRectangle desktop_bounds{};
  for (gint i = 0; i < gdk_screen_get_n_monitors(screen); ++i) {
    GdkRectangle monitor_bounds{};
    gdk_screen_get_monitor_geometry(screen, i, &monitor_bounds);
    if (i == 0) {
      desktop_bounds = monitor_bounds;
    } else {
      gdk_rectangle_union(&desktop_bounds, &monitor_bounds, &desktop_bounds);
    }
  }

  const bool horizontally_visible =
      self->window_x + 50 < desktop_bounds.x + desktop_bounds.width &&
      self->window_x + self->window_width - 50 > desktop_bounds.x;
  const bool vertically_visible =
      self->window_y + 50 < desktop_bounds.y + desktop_bounds.height &&
      self->window_y + self->window_height - 50 > desktop_bounds.y;
  if (!horizontally_visible || !vertically_visible) {
    self->window_x = desktop_bounds.x + 10;
    self->window_y = desktop_bounds.y + 10;
  }
}

static void save_window_state(MyApplication* self) {
  if (self->window == nullptr) {
    return;
  }

  g_autoptr(GKeyFile) key_file = g_key_file_new();
  g_key_file_set_integer(key_file, "window", "x", self->window_x);
  g_key_file_set_integer(key_file, "window", "y", self->window_y);
  g_key_file_set_integer(key_file, "window", "width", self->window_width);
  g_key_file_set_integer(key_file, "window", "height", self->window_height);
  g_key_file_set_boolean(key_file, "window", "maximized",
                         self->window_maximized);

  g_autofree gchar* directory =
      g_build_filename(g_get_user_config_dir(), "loliSnatcher", nullptr);
  g_mkdir_with_parents(directory, 0700);
  g_autofree gchar* path = get_window_state_path();
  g_autoptr(GError) error = nullptr;
  if (!g_key_file_save_to_file(key_file, path, &error)) {
    g_warning("Failed to save window state: %s", error->message);
  }
}

static gboolean window_configure_cb(GtkWidget*, GdkEvent* event,
                                    MyApplication* self) {
  if (!self->window_maximized) {
    const GdkEventConfigure* configure_event =
        reinterpret_cast<GdkEventConfigure*>(event);
    self->window_x = configure_event->x;
    self->window_y = configure_event->y;
    self->window_width = configure_event->width;
    self->window_height = configure_event->height;
  }
  return FALSE;
}

static gboolean window_state_cb(GtkWidget*, GdkEventWindowState* event,
                                MyApplication* self) {
  self->window_maximized =
      (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0;
  return FALSE;
}

static gboolean window_delete_cb(GtkWidget*, GdkEvent*,
                                 MyApplication* self) {
  save_window_state(self);
  return FALSE;
}

static void window_method_call_cb(FlMethodChannel*,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(fl_method_call_get_name(method_call), "reset") == 0) {
    set_default_window_state(self);
    gtk_window_unmaximize(self->window);
    gtk_window_resize(self->window, self->window_width, self->window_height);
    gtk_window_move(self->window, self->window_x, self->window_y);
    save_window_state(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "loliSnatcher");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "loliSnatcher");
  }

  set_default_window_state(self);
  load_window_state(self);
  gtk_window_set_default_size(window, self->window_width, self->window_height);
  gtk_window_move(window, self->window_x, self->window_y);
  if (self->window_maximized) {
    gtk_window_maximize(window);
  }
  gtk_widget_show(GTK_WIDGET(window));
  g_signal_connect(window, "configure-event", G_CALLBACK(window_configure_cb),
                   self);
  g_signal_connect(window, "window-state-event", G_CALLBACK(window_state_cb),
                   self);
  g_signal_connect(window, "delete-event", G_CALLBACK(window_delete_cb), self);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlMethodChannel) window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "lolisnatcher/window", FL_METHOD_CODEC(fl_standard_method_codec_new()));
  fl_method_channel_set_method_call_handler(
      window_channel, window_method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->window = nullptr;
  self->window_x = kDefaultWindowOffset;
  self->window_y = kDefaultWindowOffset;
  self->window_width = kFallbackWindowWidth;
  self->window_height = kFallbackWindowHeight;
  self->window_maximized = FALSE;
}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
