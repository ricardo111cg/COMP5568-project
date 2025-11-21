import { ethers } from 'ethers';
window.ethers = ethers;
import { useState } from 'react';
import { BrowserRouter as Router, Routes, Route, Link, useLocation } from 'react-router-dom';
import WalletConnect from './components/WalletConnect';
import Marketplace from './components/Marketplace';
import MyNFTs from './components/MyNFTs';
import './App.css';

function Navigation() {
  const location = useLocation();
  
  return (
    <nav className="bg-white border-b">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between items-center h-16">
          <div className="flex items-center gap-8">
            <Link to="/" className="text-xl font-bold text-blue-600">
              COMP5521 NFT 市场
            </Link>
            <div className="flex gap-4">
              <Link
                to="/"
                className={`px-4 py-2 rounded-lg transition-colors ${
                  location.pathname === '/'
                    ? 'bg-blue-100 text-blue-700 font-medium'
                    : 'text-gray-600 hover:text-gray-900'
                }`}
              >
                市场
              </Link>
              <Link
                to="/my-nfts"
                className={`px-4 py-2 rounded-lg transition-colors ${
                  location.pathname === '/my-nfts'
                    ? 'bg-blue-100 text-blue-700 font-medium'
                    : 'text-gray-600 hover:text-gray-900'
                }`}
              >
                我的 NFT
              </Link>
            </div>
          </div>
          <WalletConnect />
        </div>
      </div>
    </nav>
  );
}

function App() {
  return (
    <Router>
      <div className="min-h-screen bg-gray-50">
        <Navigation />
        <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <Routes>
            <Route path="/" element={<Marketplace />} />
            <Route path="/my-nfts" element={<MyNFTs />} />
          </Routes>
        </main>
      </div>
    </Router>
  );
}

export default App;

