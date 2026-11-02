/*
 * MacPlatformPlugin.h - declaration of MacPlatformPlugin class
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

#include "PluginInterface.h"
#include "PlatformPluginInterface.h"
#include "MacCoreFunctions.h"
#include "MacFilesystemFunctions.h"
#include "MacInputDeviceFunctions.h"
#include "MacNetworkFunctions.h"
#include "MacServiceFunctions.h"
#include "MacSessionFunctions.h"
#include "MacUserFunctions.h"

class MacPlatformPlugin : public QObject, PlatformPluginInterface, PluginInterface
{
	Q_OBJECT
	Q_PLUGIN_METADATA(IID "io.veyon.Veyon.Plugins.MacPlatform")
	Q_INTERFACES(PluginInterface PlatformPluginInterface)
public:
	explicit MacPlatformPlugin( QObject* parent = nullptr );
	~MacPlatformPlugin() override = default;

	Plugin::Uid uid() const override
	{
		return Plugin::Uid{ QStringLiteral("900722ef-aa30-47ad-9300-7b5446fe10e8") };
	}

	QVersionNumber version() const override
	{
		return QVersionNumber( 1, 0 );
	}

	QString name() const override
	{
		return QStringLiteral( "MacPlatformPlugin" );
	}

	QString description() const override
	{
		return tr( "Plugin implementing abstract functions for the macOS platform" );
	}

	QString vendor() const override
	{
		return QStringLiteral( "Veyon Community" );
	}

	QString copyright() const override
	{
		return QStringLiteral( "Veyon macOS port contributors" );
	}

	Plugin::Flags flags() const override
	{
		return Plugin::ProvidesDefaultImplementation;
	}

	PlatformCoreFunctions& coreFunctions() override
	{
		return m_macCoreFunctions;
	}

	PlatformFilesystemFunctions& filesystemFunctions() override
	{
		return m_macFilesystemFunctions;
	}

	PlatformInputDeviceFunctions& inputDeviceFunctions() override
	{
		return m_macInputDeviceFunctions;
	}

	PlatformNetworkFunctions& networkFunctions() override
	{
		return m_macNetworkFunctions;
	}

	PlatformServiceFunctions& serviceFunctions() override
	{
		return m_macServiceFunctions;
	}

	PlatformSessionFunctions& sessionFunctions() override
	{
		return m_macSessionFunctions;
	}

	PlatformUserFunctions& userFunctions() override
	{
		return m_macUserFunctions;
	}

private:
	MacCoreFunctions m_macCoreFunctions{};
	MacFilesystemFunctions m_macFilesystemFunctions{};
	MacInputDeviceFunctions m_macInputDeviceFunctions{};
	MacNetworkFunctions m_macNetworkFunctions{};
	MacServiceFunctions m_macServiceFunctions{};
	MacSessionFunctions m_macSessionFunctions{};
	MacUserFunctions m_macUserFunctions{};

};
