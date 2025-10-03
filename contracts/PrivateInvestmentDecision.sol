// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FHE, euint32, euint64, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract PrivateInvestmentDecision is SepoliaConfig {

    address public owner;
    uint32 public currentProjectId;

    struct InvestmentProject {
        bytes32 projectHash;
        euint64 estimatedCost;
        euint32 expectedROI;
        euint32 riskScore;
        euint32 confidenceLevel;
        bool isActive;
        bool decisionMade;
        address proposer;
        uint256 submissionTime;
        uint256 decisionDeadline;
        address[] evaluators;
    }

    struct InvestorEvaluation {
        euint32 ratingScore;
        euint32 personalROIEstimate;
        euint32 riskAssessment;
        bool hasEvaluated;
        uint256 evaluationTime;
        bytes encryptedComments;
    }

    struct ProjectDecision {
        bool approved;
        euint64 approvedBudget;
        euint32 finalROITarget;
        uint256 decisionTime;
        uint32 totalEvaluations;
        address[] approvedBy;
    }

    mapping(uint32 => InvestmentProject) public projects;
    mapping(uint32 => mapping(address => InvestorEvaluation)) public evaluations;
    mapping(uint32 => ProjectDecision) public decisions;
    mapping(address => bool) public authorizedInvestors;
    mapping(address => euint64) public investorBudgetLimits;

    event ProjectSubmitted(uint32 indexed projectId, address indexed proposer, bytes32 projectHash);
    event EvaluationSubmitted(uint32 indexed projectId, address indexed evaluator);
    event ProjectDecisionMade(uint32 indexed projectId, bool approved, uint256 decisionTime);
    event InvestorAuthorized(address indexed investor, uint256 timestamp);
    event BudgetLimitSet(address indexed investor, uint256 timestamp);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    modifier onlyAuthorizedInvestor() {
        require(authorizedInvestors[msg.sender], "Not authorized investor");
        _;
    }

    modifier onlyActiveProject(uint32 _projectId) {
        require(projects[_projectId].isActive, "Project not active");
        require(block.timestamp <= projects[_projectId].decisionDeadline, "Evaluation period ended");
        _;
    }

    modifier onlyProjectProposer(uint32 _projectId) {
        require(projects[_projectId].proposer == msg.sender, "Not project proposer");
        _;
    }

    constructor() {
        owner = msg.sender;
        currentProjectId = 1;
        authorizedInvestors[msg.sender] = true;
    }

    function authorizeInvestor(address _investor, uint64 _budgetLimit) external onlyOwner {
        authorizedInvestors[_investor] = true;

        euint64 encryptedBudgetLimit = FHE.asEuint64(_budgetLimit);
        investorBudgetLimits[_investor] = encryptedBudgetLimit;

        FHE.allowThis(encryptedBudgetLimit);
        FHE.allow(encryptedBudgetLimit, _investor);

        emit InvestorAuthorized(_investor, block.timestamp);
        emit BudgetLimitSet(_investor, block.timestamp);
    }

    function submitInvestmentProject(
        bytes32 _projectHash,
        uint64 _estimatedCost,
        uint32 _expectedROI,
        uint32 _riskScore,
        uint32 _confidenceLevel,
        uint256 _evaluationDays
    ) external onlyAuthorizedInvestor {
        require(_riskScore <= 100, "Risk score must be 0-100");
        require(_confidenceLevel <= 100, "Confidence level must be 0-100");
        require(_evaluationDays >= 1 && _evaluationDays <= 30, "Evaluation period: 1-30 days");

        euint64 encryptedCost = FHE.asEuint64(_estimatedCost);
        euint32 encryptedROI = FHE.asEuint32(_expectedROI);
        euint32 encryptedRisk = FHE.asEuint32(_riskScore);
        euint32 encryptedConfidence = FHE.asEuint32(_confidenceLevel);

        projects[currentProjectId] = InvestmentProject({
            projectHash: _projectHash,
            estimatedCost: encryptedCost,
            expectedROI: encryptedROI,
            riskScore: encryptedRisk,
            confidenceLevel: encryptedConfidence,
            isActive: true,
            decisionMade: false,
            proposer: msg.sender,
            submissionTime: block.timestamp,
            decisionDeadline: block.timestamp + (_evaluationDays * 1 days),
            evaluators: new address[](0)
        });

        FHE.allowThis(encryptedCost);
        FHE.allowThis(encryptedROI);
        FHE.allowThis(encryptedRisk);
        FHE.allowThis(encryptedConfidence);

        FHE.allow(encryptedCost, msg.sender);
        FHE.allow(encryptedROI, msg.sender);
        FHE.allow(encryptedRisk, msg.sender);
        FHE.allow(encryptedConfidence, msg.sender);

        emit ProjectSubmitted(currentProjectId, msg.sender, _projectHash);
        currentProjectId++;
    }

    function submitEvaluation(
        uint32 _projectId,
        uint32 _ratingScore,
        uint32 _personalROIEstimate,
        uint32 _riskAssessment,
        bytes calldata _encryptedComments
    ) external onlyAuthorizedInvestor onlyActiveProject(_projectId) {
        require(!evaluations[_projectId][msg.sender].hasEvaluated, "Already evaluated");
        require(_ratingScore <= 100, "Rating score must be 0-100");
        require(_riskAssessment <= 100, "Risk assessment must be 0-100");
        require(projects[_projectId].proposer != msg.sender, "Cannot evaluate own project");

        euint32 encryptedRating = FHE.asEuint32(_ratingScore);
        euint32 encryptedPersonalROI = FHE.asEuint32(_personalROIEstimate);
        euint32 encryptedRiskAssessment = FHE.asEuint32(_riskAssessment);

        evaluations[_projectId][msg.sender] = InvestorEvaluation({
            ratingScore: encryptedRating,
            personalROIEstimate: encryptedPersonalROI,
            riskAssessment: encryptedRiskAssessment,
            hasEvaluated: true,
            evaluationTime: block.timestamp,
            encryptedComments: _encryptedComments
        });

        projects[_projectId].evaluators.push(msg.sender);

        FHE.allowThis(encryptedRating);
        FHE.allowThis(encryptedPersonalROI);
        FHE.allowThis(encryptedRiskAssessment);

        FHE.allow(encryptedRating, msg.sender);
        FHE.allow(encryptedPersonalROI, msg.sender);
        FHE.allow(encryptedRiskAssessment, msg.sender);

        FHE.allow(encryptedRating, projects[_projectId].proposer);
        FHE.allow(encryptedPersonalROI, projects[_projectId].proposer);
        FHE.allow(encryptedRiskAssessment, projects[_projectId].proposer);

        emit EvaluationSubmitted(_projectId, msg.sender);
    }

    function processProjectDecision(uint32 _projectId) external onlyOwner {
        require(projects[_projectId].isActive, "Project not active");
        require(!projects[_projectId].decisionMade, "Decision already made");
        require(block.timestamp > projects[_projectId].decisionDeadline, "Evaluation period not ended");
        require(projects[_projectId].evaluators.length >= 1, "No evaluations submitted");

        InvestmentProject storage project = projects[_projectId];

        bytes32[] memory cts = new bytes32[](4);
        cts[0] = FHE.toBytes32(project.estimatedCost);
        cts[1] = FHE.toBytes32(project.expectedROI);
        cts[2] = FHE.toBytes32(project.riskScore);
        cts[3] = FHE.toBytes32(project.confidenceLevel);

        FHE.requestDecryption(cts, this.finalizeDecision.selector);
    }

    function finalizeDecision(
        uint256 requestId,
        uint64 estimatedCost,
        uint32 expectedROI,
        uint32 riskScore,
        uint32 confidenceLevel,
        bytes memory signature
    ) external {
        uint32 projectId = _findProjectByRequestId(requestId);

        bytes32[] memory cts = new bytes32[](4);
        cts[0] = FHE.toBytes32(projects[projectId].estimatedCost);
        cts[1] = FHE.toBytes32(projects[projectId].expectedROI);
        cts[2] = FHE.toBytes32(projects[projectId].riskScore);
        cts[3] = FHE.toBytes32(projects[projectId].confidenceLevel);

        bytes memory ctsBytes = abi.encode(cts);
        FHE.checkSignatures(requestId, ctsBytes, signature);

        require(projectId > 0, "Invalid project");

        InvestmentProject storage project = projects[projectId];

        bool approved = _evaluateProjectApproval(projectId, estimatedCost, expectedROI, riskScore, confidenceLevel);
        uint64 approvedBudget = approved ? estimatedCost : 0;
        uint32 finalROITarget = approved ? expectedROI : 0;

        decisions[projectId] = ProjectDecision({
            approved: approved,
            approvedBudget: FHE.asEuint64(approvedBudget),
            finalROITarget: FHE.asEuint32(finalROITarget),
            decisionTime: block.timestamp,
            totalEvaluations: uint32(project.evaluators.length),
            approvedBy: approved ? project.evaluators : new address[](0)
        });

        project.isActive = false;
        project.decisionMade = true;

        if (approved) {
            FHE.allowThis(decisions[projectId].approvedBudget);
            FHE.allowThis(decisions[projectId].finalROITarget);
            FHE.allow(decisions[projectId].approvedBudget, project.proposer);
            FHE.allow(decisions[projectId].finalROITarget, project.proposer);
        }

        emit ProjectDecisionMade(projectId, approved, block.timestamp);
    }

    function _evaluateProjectApproval(
        uint32 _projectId,
        uint64 _cost,
        uint32 _roi,
        uint32 _risk,
        uint32 _confidence
    ) private view returns (bool) {
        uint32 minROI = 15;
        uint32 maxRisk = 70;
        uint32 minConfidence = 60;
        uint64 maxCost = 1000000;

        if (_cost > maxCost) return false;
        if (_roi < minROI) return false;
        if (_risk > maxRisk) return false;
        if (_confidence < minConfidence) return false;

        uint32 evaluatorCount = uint32(projects[_projectId].evaluators.length);
        if (evaluatorCount < 2) return false;

        return true;
    }

    function _findProjectByRequestId(uint256 _requestId) private pure returns (uint32) {
        return uint32(_requestId % 1000000);
    }

    function getProjectInfo(uint32 _projectId) external view returns (
        bytes32 projectHash,
        bool isActive,
        bool decisionMade,
        address proposer,
        uint256 submissionTime,
        uint256 decisionDeadline,
        uint256 evaluatorCount
    ) {
        InvestmentProject storage project = projects[_projectId];
        return (
            project.projectHash,
            project.isActive,
            project.decisionMade,
            project.proposer,
            project.submissionTime,
            project.decisionDeadline,
            project.evaluators.length
        );
    }

    function getEvaluatorList(uint32 _projectId) external view returns (address[] memory) {
        return projects[_projectId].evaluators;
    }

    function hasUserEvaluated(uint32 _projectId, address _user) external view returns (bool) {
        return evaluations[_projectId][_user].hasEvaluated;
    }

    function getDecisionResult(uint32 _projectId) external view returns (
        bool approved,
        uint256 decisionTime,
        uint32 totalEvaluations
    ) {
        ProjectDecision storage decision = decisions[_projectId];
        return (
            decision.approved,
            decision.decisionTime,
            decision.totalEvaluations
        );
    }

    function isAuthorizedInvestor(address _investor) external view returns (bool) {
        return authorizedInvestors[_investor];
    }

    function getCurrentProjectId() external view returns (uint32) {
        return currentProjectId;
    }

    function getActiveProjectsCount() external view returns (uint32) {
        uint32 count = 0;
        for (uint32 i = 1; i < currentProjectId; i++) {
            if (projects[i].isActive && block.timestamp <= projects[i].decisionDeadline) {
                count++;
            }
        }
        return count;
    }
}