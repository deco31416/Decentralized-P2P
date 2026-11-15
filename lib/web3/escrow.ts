/**
 * INTEGRACIÓN WEB3 DE ESCROW P2P
 * Sin backend - Todo on-chain usando Thirdweb
 */

import { prepareContractCall, sendTransaction } from 'thirdweb'
import { getEscrowContract, getUSDTContract } from '@/lib/contracts'
import type { Account } from 'thirdweb/wallets'

// ============================================
// TIPOS
// ============================================

export interface CreateOrderParams {
  tokenAddress: string
  amount: bigint
  price: bigint
  isBuyOrder: boolean
  paymentMethod: string
}

export interface AcceptOrderParams {
  orderId: bigint
}

export interface CompleteOrderParams {
  orderId: bigint
}

export interface DisputeOrderParams {
  orderId: bigint
  reason: string
}

// ============================================
// FUNCIONES DE ESCROW
// ============================================

/**
 * Crear una orden P2P
 */
export async function createP2POrder(account: Account, params: CreateOrderParams) {
  try {
    const escrowContract = getEscrowContract()

    // 1. Aprobar tokens si es necesario (para órdenes de venta)
    if (!params.isBuyOrder) {
      const tokenContract = getUSDTContract() // O el token que sea
      const approveTx = prepareContractCall({
        contract: tokenContract,
        method: 'function approve(address spender, uint256 amount) returns (bool)',
        params: [escrowContract.address, params.amount]
      })

      await sendTransaction({
        transaction: approveTx,
        account
      })
    }

    // 2. Crear la orden
    const createOrderTx = prepareContractCall({
      contract: escrowContract,
      method:
        'function createOrder(address token, uint256 amount, uint256 price, bool isBuy, string memory paymentMethod) returns (uint256)',
      params: [params.tokenAddress, params.amount, params.price, params.isBuyOrder, params.paymentMethod]
    })

    const result = await sendTransaction({
      transaction: createOrderTx,
      account
    })

    return {
      success: true,
      transactionHash: result.transactionHash,
      message: 'Orden creada exitosamente'
    }
  } catch (error) {
    console.error('Error creating order:', error)
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Error desconocido'
    }
  }
}

/**
 * Aceptar una orden P2P
 */
export async function acceptP2POrder(account: Account, params: AcceptOrderParams) {
  try {
    const escrowContract = getEscrowContract()

    const acceptOrderTx = prepareContractCall({
      contract: escrowContract,
      method: 'function acceptOrder(uint256 orderId) payable',
      params: [params.orderId]
    })

    const result = await sendTransaction({
      transaction: acceptOrderTx,
      account
    })

    return {
      success: true,
      transactionHash: result.transactionHash,
      message: 'Orden aceptada. Realiza el pago fiat.'
    }
  } catch (error) {
    console.error('Error accepting order:', error)
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Error desconocido'
    }
  }
}

/**
 * Completar una orden P2P (después del pago fiat)
 */
export async function completeP2POrder(account: Account, params: CompleteOrderParams) {
  try {
    const escrowContract = getEscrowContract()

    const completeOrderTx = prepareContractCall({
      contract: escrowContract,
      method: 'function completeOrder(uint256 orderId)',
      params: [params.orderId]
    })

    const result = await sendTransaction({
      transaction: completeOrderTx,
      account
    })

    return {
      success: true,
      transactionHash: result.transactionHash,
      message: 'Orden completada. Fondos liberados.'
    }
  } catch (error) {
    console.error('Error completing order:', error)
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Error desconocido'
    }
  }
}

/**
 * Crear disputa
 */
export async function createDispute(account: Account, params: DisputeOrderParams) {
  try {
    const escrowContract = getEscrowContract()

    const disputeTx = prepareContractCall({
      contract: escrowContract,
      method: 'function createDispute(uint256 orderId, string memory reason)',
      params: [params.orderId, params.reason]
    })

    const result = await sendTransaction({
      transaction: disputeTx,
      account
    })

    return {
      success: true,
      transactionHash: result.transactionHash,
      message: 'Disputa creada. Esperando resolución.'
    }
  } catch (error) {
    console.error('Error creating dispute:', error)
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Error desconocido'
    }
  }
}

/**
 * Obtener órdenes activas (usando Thirdweb's read function)
 */
export async function getActiveOrders() {
  try {
    // const escrowContract = getEscrowContract()

    // Thirdweb maneja la lectura automáticamente
    // const orders = await readContract({
    //   contract: escrowContract,
    //   method: "function getActiveOrders() view returns (tuple[])",
    //   params: [],
    // });

    // return orders;

    // Por ahora retornamos mock hasta que el contrato esté deployado
    return []
  } catch (error) {
    console.error('Error getting orders:', error)
    return []
  }
}

