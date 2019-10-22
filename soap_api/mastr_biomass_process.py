#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
BNetzA - MaStR Processing Biomass

Process MaStR data from CSV

SPDX-License-Identifier: AGPL-3.0-or-later
"""

__copyright__ = "© Reiner Lemoine Institut"
__license__ = "GNU Affero General Public License Version 3 (AGPL-3.0)"
__url__ = "https://www.gnu.org/licenses/agpl-3.0.en.html"
__author__ = "Ludee; christian-rli"
__issue__ = "https://github.com/OpenEnergyPlatform/examples/issues/52"
__version__ = "v0.8.0"

import logging
from soap_api.mastr_power_unit_download import read_power_units
from soap_api.mastr_biomass_download import read_unit_biomass, read_unit_biomass_eeg
from soap_api.utils import (
    write_to_csv,
    fname_power_unit_biomass,
    fname_unit_biomass,
    fname_unit_biomass_eeg,
    fname_biomass_all
)

log = logging.getLogger(__name__)


def make_biomass():
    """Read biomass data from CSV files. Join data and write to file."""
    data_version = get_data_version()
    csv_biomass = f'data/bnetza_mastr_{data_version}_biomass_all.csv'

    power_unit_biomass = read_power_units(fname_biomass_unit)
    unit_biomass = read_unit_biomass(fname_biomass)
    unit_biomass_eeg = read_unit_biomass_eeg(fname_biomass_eeg)

    table_biomass = power_unit_biomass.set_index('EinheitMastrNummer') \
        .join(unit_biomass.set_index('EinheitMastrNummer'),
              on='EinheitMastrNummer', how='left', rsuffix='_w') \
        .join(unit_biomass_eeg.set_index('EegMastrNummer'),
              on='EegMastrNummer', how='left', rsuffix='_e')

    write_to_csv(csv_biomass, table_biomass)
    log.info(f'Join Biomass to: {csv_biomass}')
