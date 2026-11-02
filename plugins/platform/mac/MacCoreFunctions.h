/*
 * MacCoreFunctions.h - declaration of MacCoreFunctions class
 *
 * Copyright (c) 2026 Veyon macOS port contributors
 *
 * This file is part of Veyon - https://veyon.io
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program (see COPYING); if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 */

#pragma once

#include <os/log.h>

#include "PlatformCoreFunctions.h"

// clazy:excludeall=copyable-polymorphic

class MacCoreFunctions : public PlatformCoreFunctions
{
public:
	bool applyConfiguration() override;

	bool prepareSessionBusAccess() override;

	void initNativeLoggingSystem( const QString& appName ) override;
	void writeToNativeLoggingSystem( const QString& message, Logger::LogLevel loglevel ) override;

	StandardInputReader* createStandardInputReader(QObject* parent) override;

	void reboot() override;
	void powerDown( bool installUpdates ) override;

	void raiseWindow( QWidget* widget, bool stayOnTop ) override;

	void disableScreenSaver() override;
	void restoreScreenSaverSettings() override;

	void setSystemUiState( bool enabled ) override;

	QString activeDesktopName() override;

	bool isRunningAsAdmin() const override;
	bool runProgramAsAdmin( const QString& program, const QStringList& parameters ) override;

	bool runProgramAsUser(const QString& program, const QStringList& parameters,
						  const QString& username,
						  const QString& desktop,
						  const QByteArray& stdInData) override;

	QString genericUrlHandler() const override;

	QString queryDisplayDeviceName(const QScreen& screen) const override;

	QString getApplicationName(ProcessId processId) const override;

	static int runAppleScript( const QStringList& statements, const QStringList& arguments = {} );
	static bool sendLoginWindowEvent( const QString& eventCode );

private:
	os_log_t m_logHandle{nullptr};

	// IOPMAssertionID (uint32_t) - not using the IOKit type here to keep IOKit headers out
	quint32 m_displaySleepAssertion{0};
	bool m_displaySleepAssertionActive{false};

};
