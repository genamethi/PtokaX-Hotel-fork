/*
 * PtokaX - hub server for Direct Connect peer to peer network.

 * Copyright (C) 2004-2022  Petr Kozelka, PPK at PtokaX dot org

 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3
 * as published by the Free Software Foundation.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
//---------------------------------------------------------------------------
#ifndef PingerInfoH
#define PingerInfoH
//---------------------------------------------------------------------------

// hubinfo.json for the pinger endpoint described in
// direct-connect/protocols, http/ping.md. The hub has no HTTP server, so it
// writes the file and the reverse proxy serves it at /api/v0/hubinfo.json.
//
// PingerAddresses supplies the addr array. The hub cannot know its own public
// TLS URL, so an empty setting means nothing is written.
void PingerWriteInfo();

//---------------------------------------------------------------------------
#endif
