#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

typedef char gchar;
typedef int gint;
typedef int gboolean;
typedef void* gpointer;
typedef struct _GVariant GVariant;
typedef struct _GVariantType GVariantType;
typedef struct _GDBusConnection GDBusConnection;
typedef struct _GDBusMethodInvocation GDBusMethodInvocation;
typedef struct _GError GError;
typedef struct _GMainLoop GMainLoop;
typedef struct _GMainContext GMainContext;

typedef struct {
    gint ref_count;
    gchar *name;
    void **methods;
    void **signals;
    void **properties;
    void **annotations;
} GDBusInterfaceInfo;

typedef struct {
    gint ref_count;
    gchar *path;
    GDBusInterfaceInfo **interfaces;
    void **nodes;
    void **annotations;
} GDBusNodeInfo;

typedef struct {
    union {
        struct {
            uintptr_t partial_magic;
            const GVariantType *type;
            uintptr_t y[14];
        } s;
        uintptr_t x[16];
    } u;
} GVariantBuilder;

typedef void (*GDBusInterfaceMethodCallFunc)(
    GDBusConnection *connection,
    const gchar *sender,
    const gchar *object_path,
    const gchar *interface_name,
    const gchar *method_name,
    GVariant *parameters,
    GDBusMethodInvocation *invocation,
    gpointer user_data);

typedef GVariant *(*GDBusInterfaceGetPropertyFunc)(
    GDBusConnection *connection,
    const gchar *sender,
    const gchar *object_path,
    const gchar *interface_name,
    const gchar *property_name,
    GError **error,
    gpointer user_data);

typedef gboolean (*GDBusInterfaceSetPropertyFunc)(
    GDBusConnection *connection,
    const gchar *sender,
    const gchar *object_path,
    const gchar *interface_name,
    const gchar *property_name,
    GVariant *value,
    GError **error,
    gpointer user_data);

typedef struct {
    GDBusInterfaceMethodCallFunc method_call;
    GDBusInterfaceGetPropertyFunc get_property;
    GDBusInterfaceSetPropertyFunc set_property;
    gpointer padding[8];
} GDBusInterfaceVTable;

typedef void (*GBusAcquiredCallback)(GDBusConnection *connection, const gchar *name, gpointer user_data);
typedef void (*GBusNameAcquiredCallback)(GDBusConnection *connection, const gchar *name, gpointer user_data);
typedef void (*GBusNameLostCallback)(GDBusConnection *connection, const gchar *name, gpointer user_data);
typedef void (*GDestroyNotify)(gpointer data);

extern GVariant *g_variant_new_int32(int32_t value);
extern int32_t g_variant_get_int32(GVariant *value);
extern GVariant *g_variant_new(const gchar *format_string, ...);
extern void g_variant_builder_init(GVariantBuilder *builder, const GVariantType *type);
extern void g_variant_builder_add(GVariantBuilder *builder, const gchar *format_string, ...);
extern GDBusNodeInfo *g_dbus_node_info_new_for_xml(const gchar *xml_data, GError **error);
extern unsigned int g_dbus_connection_register_object(
    GDBusConnection *connection,
    const gchar *object_path,
    GDBusInterfaceInfo *interface_info,
    const GDBusInterfaceVTable *vtable,
    gpointer user_data,
    GDestroyNotify user_data_free_func,
    GError **error);
extern gboolean g_dbus_connection_emit_signal(
    GDBusConnection *connection,
    const gchar *destination_bus_name,
    const gchar *object_path,
    const gchar *interface_name,
    const gchar *signal_name,
    GVariant *parameters,
    GError **error);
extern void g_dbus_method_invocation_return_value(GDBusMethodInvocation *invocation, GVariant *parameters);
extern unsigned int g_bus_own_name(
    int bus_type,
    const gchar *name,
    int flags,
    GBusAcquiredCallback bus_acquired_handler,
    GBusNameAcquiredCallback name_acquired_handler,
    GBusNameLostCallback name_lost_handler,
    gpointer user_data,
    GDestroyNotify user_data_free_func);
extern GMainLoop *g_main_loop_new(GMainContext *context, gboolean is_running);
extern void g_main_loop_run(GMainLoop *loop);

static int current_pct = 65;

static const gchar introspection_xml[] =
    "<node>"
    "  <interface name='org.gnome.SettingsDaemon.Power.Screen'>"
    "    <method name='StepUp'>"
    "      <arg type='i' name='new_percentage' direction='out'/>"
    "      <arg type='s' name='connector' direction='out'/>"
    "    </method>"
    "    <method name='StepDown'>"
    "      <arg type='i' name='new_percentage' direction='out'/>"
    "      <arg type='s' name='connector' direction='out'/>"
    "    </method>"
    "    <property name='Brightness' type='i' access='readwrite'/>"
    "  </interface>"
    "</node>";

static void write_hw_brightness(int pct) {
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    current_pct = pct;
    int hw = 80 + (pct * 3420) / 100;
    FILE *f = fopen("/sys/class/backlight/panel0-backlight/brightness", "w");
    if (f) {
        fprintf(f, "%d\n", hw);
        fclose(f);
    }
}

static void emit_brightness_changed(GDBusConnection *conn) {
    GVariantBuilder builder;
    g_variant_builder_init(&builder, (const GVariantType *)"a{sv}");
    g_variant_builder_add(&builder, "{sv}", "Brightness", g_variant_new_int32(current_pct));
    g_dbus_connection_emit_signal(
        conn,
        NULL,
        "/org/gnome/SettingsDaemon/Power",
        "org.freedesktop.DBus.Properties",
        "PropertiesChanged",
        g_variant_new("(sa{sv}as)", "org.gnome.SettingsDaemon.Power.Screen", &builder, NULL),
        NULL);
}

static void handle_method_call(
    GDBusConnection *conn,
    const gchar *sender,
    const gchar *object_path,
    const gchar *interface_name,
    const gchar *method_name,
    GVariant *parameters,
    GDBusMethodInvocation *invocation,
    gpointer user_data)
{
    if (strcmp(method_name, "StepUp") == 0) {
        write_hw_brightness(current_pct + 10);
        emit_brightness_changed(conn);
        g_dbus_method_invocation_return_value(invocation, g_variant_new("(is)", current_pct, "DSI-1"));
    } else if (strcmp(method_name, "StepDown") == 0) {
        write_hw_brightness(current_pct - 10);
        emit_brightness_changed(conn);
        g_dbus_method_invocation_return_value(invocation, g_variant_new("(is)", current_pct, "DSI-1"));
    }
}

static GVariant *handle_get_property(
    GDBusConnection *conn,
    const gchar *sender,
    const gchar *object_path,
    const gchar *interface_name,
    const gchar *property_name,
    GError **error,
    gpointer user_data)
{
    if (strcmp(property_name, "Brightness") == 0) {
        return g_variant_new_int32(current_pct);
    }
    return NULL;
}

static gboolean handle_set_property(
    GDBusConnection *conn,
    const gchar *sender,
    const gchar *object_path,
    const gchar *interface_name,
    const gchar *property_name,
    GVariant *value,
    GError **error,
    gpointer user_data)
{
    if (strcmp(property_name, "Brightness") == 0) {
        int pct = g_variant_get_int32(value);
        write_hw_brightness(pct);
        emit_brightness_changed(conn);
        return 1;
    }
    return 0;
}

static const GDBusInterfaceVTable interface_vtable = {
    handle_method_call,
    handle_get_property,
    handle_set_property,
    { 0 }
};

static void on_bus_acquired(GDBusConnection *conn, const gchar *name, gpointer user_data) {
    GDBusNodeInfo *introspection_data = g_dbus_node_info_new_for_xml(introspection_xml, NULL);
    g_dbus_connection_register_object(
        conn,
        "/org/gnome/SettingsDaemon/Power",
        introspection_data->interfaces[0],
        &interface_vtable,
        NULL,
        NULL,
        NULL);
}

int main(int argc, char **argv) {
    FILE *f = fopen("/sys/class/backlight/panel0-backlight/brightness", "r");
    if (f) {
        int hw = 2200;
        if (fscanf(f, "%d", &hw) == 1) {
            int pct = ((hw - 80) * 100) / 3420;
            if (pct < 5) pct = 65;
            if (pct > 100) pct = 100;
            current_pct = pct;
        }
        fclose(f);
    }
    write_hw_brightness(current_pct);

    GMainLoop *loop = g_main_loop_new(NULL, 0);
    /* G_BUS_TYPE_SESSION = 2, G_BUS_NAME_OWNER_FLAGS_ALLOW_REPLACEMENT | REPLACE = 3 */
    g_bus_own_name(
        2,
        "org.gnome.SettingsDaemon.Power",
        3,
        on_bus_acquired,
        NULL,
        NULL,
        NULL,
        NULL);
    g_main_loop_run(loop);
    return 0;
}
