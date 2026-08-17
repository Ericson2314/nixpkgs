/*
 * ditree -- walk the device tree and say what state every node is in.
 *
 * This exists because devfs only shows *attached* nodes, so a driver that
 * binds and then fails attach(9E) is indistinguishable from a device that is
 * not there at all: /devices/pci@0,0/ simply contains nothing but isa@1, and
 * nothing anywhere says why. libdevinfo can see the whole devinfo tree,
 * including nodes devfs hides, so it can tell "no such device" apart from
 * "device present, driver bound, attach failed" -- which are very different
 * problems.
 *
 * prtconf(8) would do this, but it is a much larger program with a much
 * larger dependency tail; this is the part of it that matters here.
 *
 * DINFOFORCE is the point: it makes the snapshot *force an attach* of nodes
 * that are not currently attached, so the failure is provoked while we watch
 * rather than having happened silently at boot.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libdevinfo.h>

static void
print_state(uint_t st)
{
	int first = 1;

	/*
	 * di_state() reports what is *wrong* with a node; a fully attached,
	 * online node has none of these bits.
	 */
	if (st & DI_DRIVER_DETACHED) {
		(void) printf("%sDETACHED", first ? "" : ",");
		first = 0;
	}
	if (st & DI_DEVICE_OFFLINE) {
		(void) printf("%sOFFLINE", first ? "" : ",");
		first = 0;
	}
	if (st & DI_DEVICE_DOWN) {
		(void) printf("%sDOWN", first ? "" : ",");
		first = 0;
	}
	if (st & DI_BUS_QUIESCED) {
		(void) printf("%sBUS_QUIESCED", first ? "" : ",");
		first = 0;
	}
	if (st & DI_BUS_DOWN) {
		(void) printf("%sBUS_DOWN", first ? "" : ",");
		first = 0;
	}
	if (first)
		(void) printf("attached");
}

static void
walk(di_node_t node, int depth)
{
	di_node_t child;

	for (; node != DI_NODE_NIL; node = di_sibling_node(node)) {
		char *name = di_node_name(node);
		char *bind = di_binding_name(node);
		char *drv = di_driver_name(node);
		char *path = di_devfs_path(node);
		int inst = di_instance(node);

		/*
		 * Both names, because they answer different questions and
		 * confusing them wastes a lot of time. di_binding_name() is
		 * the string the node bound *by* -- for an alias binding that
		 * is the alias itself, e.g. "pci1af4,1", which looks exactly
		 * like an unbound node whose name is also "pci1af4,1".
		 * di_driver_name() is the driver that actually claimed it, so
		 * it is the one that says whether a binding happened at all.
		 */
		(void) printf("%*s%-22s bind=%-16s drv=%-9s inst=%-3d state=",
		    depth * 2, "",
		    name ? name : "?",
		    bind ? bind : "(none)",
		    drv ? drv : "(NONE)",
		    inst);
		print_state(di_state(node));

		/*
		 * A node that never reached DS_INITIALIZED has no unit
		 * address, so its path is the bare node name. That is the
		 * signature of "bound but never initialised", and it is worth
		 * seeing next to the state bits.
		 */
		if (path != NULL) {
			(void) printf("  path=%s", path);
			di_devfs_path_free(path);
		}
		(void) printf("\n");

		/*
		 * The `compatible` property, for any node no driver claimed.
		 *
		 * This is the list the system matches /etc/driver_aliases
		 * against, in order, so it is the only way to know which alias
		 * string a device would actually have needed. Guessing at it
		 * from the PCI IDs is how one ends up writing plausible
		 * aliases that match nothing -- the names here are built from
		 * subsystem IDs and class codes as well as vendor/device, and
		 * differ between the `pci` and `pciex` nexus.
		 */
		if (drv == NULL) {
			char *compat;
			int n = di_prop_lookup_strings(DDI_DEV_T_ANY, node,
			    "compatible", &compat);
			int i;

			for (i = 0; i < n; i++) {
				(void) printf("%*s    compat[%d]=%s\n",
				    depth * 2, "", i, compat);
				compat += strlen(compat) + 1;
			}
		}

		child = di_child_node(node);
		if (child != DI_NODE_NIL)
			walk(child, depth + 1);
	}
}

int
main(int argc, char **argv)
{
	const char *root = (argc > 1) ? argv[1] : "/";
	di_node_t top;

	/*
	 * DINFOCPYALL for the properties, DINFOFORCE to provoke an attach of
	 * anything currently detached. Without FORCE this reports the tree as
	 * it already is and the interesting failure never happens while we are
	 * looking.
	 */
	top = di_init(root, DINFOCPYALL | DINFOFORCE);
	if (top == DI_NODE_NIL) {
		perror("di_init");
		return (1);
	}

	walk(top, 0);
	di_fini(top);
	return (0);
}
