/**
 * CONTRATOS INTELIGENTES - CAMBIACRIPTO
 * Deploy estos contratos en Thirdweb Dashboard: https://thirdweb.com/dashboard
 * Luego actualiza las addresses aquí
 */

import { getContract } from 'thirdweb'
import { polygon } from 'thirdweb/chains'
import { client } from '@/app/hooks/client'

// ============================================
// ADDRESSES DE CONTRATOS (Actualizar después del deploy)
// ============================================
const CONTRACTS = {
  // P2P Escrow Contract
  ESCROW: {
    address: '0x0000000000000000000000000000000000000000', // ← Actualizar después del deploy
    chain: polygon
  },

  // Staking Contract
  STAKING: {
    address: '0x0000000000000000000000000000000000000000', // ← Actualizar
    chain: polygon
  },

  // IDO Token Contract
  IDO_TOKEN: {
    address: '0x0000000000000000000000000000000000000000', // ← Actualizar
    chain: polygon
  },

  // Governance Contract
  GOVERNANCE: {
    address: '0x0000000000000000000000000000000000000000', // ← Actualizar
    chain: polygon
  },

  // USDT en Polygon (ya existe)
  USDT: {
    address: '0xc2132D05D31c914a87C6611C10748AEb04B58e8F',
    chain: polygon
  }
}

// ============================================
// FUNCIONES HELPER PARA OBTENER CONTRATOS
// ============================================

/**
 * Obtiene el contrato de Escrow P2P
 */
export function getEscrowContract() {
  return getContract({
    client,
    chain: CONTRACTS.ESCROW.chain,
    address: CONTRACTS.ESCROW.address
  })
}

/**
 * Obtiene el contrato de Staking
 */
export function getStakingContract() {
  return getContract({
    client,
    chain: CONTRACTS.STAKING.chain,
    address: CONTRACTS.STAKING.address
  })
}

/**
 * Obtiene el contrato de IDO Token
 */
export function getIDOTokenContract() {
  return getContract({
    client,
    chain: CONTRACTS.IDO_TOKEN.chain,
    address: CONTRACTS.IDO_TOKEN.address
  })
}

/**
 * Obtiene el contrato de Governance
 */
export function getGovernanceContract() {
  return getContract({
    client,
    chain: CONTRACTS.GOVERNANCE.chain,
    address: CONTRACTS.GOVERNANCE.address
  })
}

/**
 * Obtiene el contrato de USDT en Polygon
 */
export function getUSDTContract() {
  return getContract({
    client,
    chain: CONTRACTS.USDT.chain,
    address: CONTRACTS.USDT.address
  })
}

// ============================================
// EXPORTAR TODAS LAS ADDRESSES
// ============================================
export const CONTRACT_ADDRESSES = CONTRACTS
