/**
 * Bristlecone Test Tools for Databases
 * Copyright (C) 2011 Continuent Inc.
 * Contact: bristlecone@lists.forge.continuent.org
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of version 2 of the GNU General Public License as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA
 *
 * Initial developer(s): Robert Hodges
 * Contributor(s):
 */

package com.continuent.bristlecone.croc;

/**
 * An exception that indicates a single test failure. It terminates the current
 * test but does not terminate the croc run.
 * 
 * @author rhodges
 */
public class CrocException extends Exception
{
    private static final long serialVersionUID = 1L;

    public CrocException(String msg)
    {
        super(msg);
    }

    public CrocException(String msg, Exception e)
    {
        super(msg, e);
    }
}
