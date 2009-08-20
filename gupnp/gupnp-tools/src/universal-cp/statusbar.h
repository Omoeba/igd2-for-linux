/*
 * statusbar.h
 *
 *  Created on: May 19, 2009
 *      Author: vlillvis
 */

#ifndef STATUSBAR_H_
#define STATUSBAR_H_

#include <glade/glade.h>
#include <gtk/gtkstatusbar.h>

void
statusbar_update (gboolean device_selected);

void
init_statusbar (GladeXML *glade_xml);

#endif /* STATUSBAR_H_ */
